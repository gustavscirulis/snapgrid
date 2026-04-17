import AppKit
import Foundation

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openai
    case anthropic
    case gemini
    case openrouter

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        }
    }

    var keychainService: String { rawValue }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.0-flash"
        case .openrouter: return "openai/gpt-4o"
        }
    }
}

// Import the PatternTag and AnalysisResult types from Models
// (They should already be available since they're in the same module)

final class AIAnalysisService: Sendable {
    static let shared = AIAnalysisService()

    private let masterSystemPrompt = """
    You are an expert AI in analyzing images. Your task is to analyze the content of images and provide appropriate descriptions.

    Provide your response in the following JSON format:
    {
      "imageContext": "Detailed description of the entire image, including its purpose and main characteristics",
      "imageSummary": "Very brief summary (1-2 words) of the main content or purpose",
      "patterns": [
        {
          "name": "Main object, subject, or element",
          "confidence": 0.95
        }
      ]
    }

    Guidelines:
      1. The "imageSummary" should be a very brief (1-2 words) description of what the image shows
      2. The "imageContext" should provide detailed information about the entire image
      3. List the most prominent objects, subjects, or elements visible in the image
      4. Use specific, descriptive language appropriate to the content (e.g. technical terms for UI screenshots, descriptive language for photos)
      5. Each pattern should be 1-2 words maximum, not duplicative of imageSummary
      6. Include confidence scores between 0.8 and 1.0
      7. List patterns in order of confidence/importance
      8. Ensure that the patterns are unique and not duplicates of each other and imageSummary
      9. Provide exactly 6 patterns, ordered by confidence
      10. Respond with a strict, valid JSON object — do not include markdown formatting, explanations, or code block symbols
      11. Use title case for pattern/object names
      12. Provide up to 6 patterns, ordered by confidence
    """

    static let defaultGuidance = "If it's a UI screenshot, focus on UI patterns and components. If it's a general scene, focus on objects and subjects."

    private let userText = "Analyze this image."

    private let maxRetries = 2

    func analyze(image: NSImage, provider: AIProvider, model: String, guidance: String? = nil, spaceContext: String? = nil) async throws -> AnalysisResult {
        guard let apiKey = try KeychainService.get(service: provider.keychainService) else {
            throw AnalysisError.noAPIKey
        }

        guard let base64 = imageToBase64(image) else {
            throw AnalysisError.imageConversionFailed
        }

        let prompt = buildPrompt(guidance: guidance, spaceContext: spaceContext)

        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = Double(attempt) * 2.0
                try? await Task.sleep(for: .seconds(delay))
                print("[Analysis] Retry attempt \(attempt)")
            }
            do {
                let req = buildProviderRequest(
                    provider: provider, apiKey: apiKey, model: model,
                    base64Image: base64, prompt: prompt
                )
                let responseText = try await sendProviderRequest(req)
                return try parseResponse(responseText, provider: provider.rawValue, model: model)
            } catch {
                lastError = error
                // Only retry on transient network/server errors
                if !isRetryable(error) { throw error }
            }
        }
        throw lastError!
    }

    func isRetryable(_ error: Error) -> Bool {
        // NSURLError connection lost, timed out, network connection lost
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [-1001, -1005, -1009].contains(nsError.code)
        }
        // 502/503/429 from API
        if case AnalysisError.apiError(let code, _) = error {
            return [429, 502, 503].contains(code)
        }
        return false
    }

    func analyzeVideo(frames: [NSImage], provider: AIProvider, model: String, guidance: String? = nil, spaceContext: String? = nil) async throws -> AnalysisResult {
        // Analyze each frame and merge results
        var allPatterns: [String: [Double]] = [:]
        var contexts: [String] = []
        var summaries: [String] = []

        for frame in frames {
            let result = try await analyze(image: frame, provider: provider, model: model, guidance: guidance, spaceContext: spaceContext)
            contexts.append(result.imageContext)
            summaries.append(result.imageSummary)

            for pattern in result.patterns {
                allPatterns[pattern.name, default: []].append(pattern.confidence)
            }
        }

        return Self.mergeFrameResults(
            allPatterns: allPatterns,
            contexts: contexts,
            summaries: summaries,
            provider: provider.rawValue,
            model: model
        )
    }

    /// Merge analysis results from multiple video frames. Averages confidence per pattern,
    /// filters below 0.7, caps at 10, sorts descending.
    static func mergeFrameResults(
        allPatterns: [String: [Double]],
        contexts: [String],
        summaries: [String],
        provider: String,
        model: String
    ) -> AnalysisResult {
        let mergedPatterns = allPatterns.map { name, confidences in
            PatternTag(name: name, confidence: confidences.reduce(0, +) / Double(confidences.count))
        }
        .filter { $0.confidence >= 0.7 }
        .sorted { $0.confidence > $1.confidence }
        .prefix(10)

        return AnalysisResult(
            imageContext: contexts.joined(separator: "\n\n"),
            imageSummary: summaries.first ?? "Video",
            patterns: Array(mergedPatterns),
            provider: provider,
            model: model
        )
    }

    // MARK: - Provider Request Infrastructure

    private struct ProviderRequest {
        let url: URL
        let headers: [String: String]
        let body: [String: Any]
        let extractText: ([String: Any]) throws -> String
    }

    private func buildProviderRequest(
        provider: AIProvider, apiKey: String, model: String,
        base64Image: String, prompt: String
    ) -> ProviderRequest {
        switch provider {
        case .openai:
            return ProviderRequest(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                headers: ["Authorization": "Bearer \(apiKey)"],
                body: [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": prompt],
                        ["role": "user", "content": [
                            ["type": "text", "text": userText],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]]
                    ],
                    "max_completion_tokens": 800
                ],
                extractText: Self.extractOpenAIText
            )
        case .anthropic:
            return ProviderRequest(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
                body: [
                    "model": model,
                    "max_tokens": 800,
                    "system": prompt,
                    "messages": [
                        ["role": "user", "content": [
                            ["type": "image", "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]],
                            ["type": "text", "text": userText]
                        ]]
                    ]
                ],
                extractText: { json in
                    let content = json["content"] as? [[String: Any]]
                    guard let text = content?.first?["text"] as? String else {
                        throw AnalysisError.invalidResponse
                    }
                    return text
                }
            )
        case .gemini:
            return ProviderRequest(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                headers: ["x-goog-api-key": apiKey],
                body: [
                    "contents": [
                        ["parts": [
                            ["text": userText],
                            ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]]
                        ]]
                    ],
                    "systemInstruction": ["parts": [["text": prompt]]],
                    "generationConfig": ["maxOutputTokens": 800]
                ],
                extractText: { json in
                    let candidates = json["candidates"] as? [[String: Any]]
                    let content = candidates?.first?["content"] as? [String: Any]
                    let parts = content?["parts"] as? [[String: Any]]
                    guard let text = parts?.first?["text"] as? String else {
                        throw AnalysisError.invalidResponse
                    }
                    return text
                }
            )
        case .openrouter:
            return ProviderRequest(
                url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "HTTP-Referer": "https://snapgrid.app",
                    "X-Title": "SnapGrid"
                ],
                body: [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": prompt],
                        ["role": "user", "content": [
                            ["type": "text", "text": userText],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]]
                    ],
                    "max_tokens": 1200
                ],
                extractText: Self.extractOpenAIText
            )
        }
    }

    /// Shared text extractor for OpenAI-compatible response formats (OpenAI, OpenRouter)
    private static func extractOpenAIText(_ json: [String: Any]) throws -> String {
        let choices = json["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AnalysisError.invalidResponse
        }
        return content
    }

    private func sendProviderRequest(_ req: ProviderRequest) async throws -> String {
        var request = URLRequest(url: req.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in req.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: req.body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalysisError.invalidResponse
        }
        return try req.extractText(json)
    }

    // MARK: - Helpers

    func buildPrompt(guidance: String? = nil, spaceContext: String? = nil) -> String {
        let effectiveGuidance = (guidance?.isEmpty == false ? guidance : nil) ?? Self.defaultGuidance
        var result = masterSystemPrompt + "\n\nGuidance:\n" + effectiveGuidance
        if let spaceContext, !spaceContext.isEmpty {
            result += "\n" + spaceContext
        }
        return result
    }

    /// Max dimension recommended by Anthropic — larger images are resized server-side anyway.
    private let maxImageDimension: CGFloat = 1568

    private func imageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let w = CGFloat(bitmapRep.pixelsWide)
        let h = CGFloat(bitmapRep.pixelsHigh)
        let longest = max(w, h)

        let targetRep: NSBitmapImageRep
        if longest > maxImageDimension {
            let scale = maxImageDimension / longest
            let newW = Int(w * scale)
            let newH = Int(h * scale)
            guard let resized = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: newW,
                pixelsHigh: newH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
            NSGraphicsContext.current?.imageInterpolation = .high
            bitmapRep.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
            NSGraphicsContext.restoreGraphicsState()
            targetRep = resized
        } else {
            targetRep = bitmapRep
        }

        guard let jpegData = targetRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalysisError.apiError(statusCode: httpResponse.statusCode, message: body)
        }
    }

    func parseResponse(_ text: String, provider: String, model: String) throws -> AnalysisResult {
        // Strip markdown code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // Remove opening fence (with optional language tag)
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            // Remove closing fence
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw AnalysisError.parseFailed
        }

        struct AIResponse: Decodable {
            let imageContext: String
            let imageSummary: String
            let patterns: [PatternEntry]

            struct PatternEntry: Decodable {
                let name: String
                let confidence: Double
            }
        }

        let decoded = try JSONDecoder().decode(AIResponse.self, from: data)

        let patterns = decoded.patterns
            .filter { $0.confidence >= 0.7 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(6)
            .map { PatternTag(name: $0.name, confidence: $0.confidence) }

        return AnalysisResult(
            imageContext: decoded.imageContext,
            imageSummary: decoded.imageSummary,
            patterns: patterns,
            provider: provider,
            model: model
        )
    }

    enum AnalysisError: LocalizedError {
        case noAPIKey
        case imageConversionFailed
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured"
            case .imageConversionFailed: return "Failed to convert image for analysis"
            case .invalidResponse: return "Invalid response from AI provider"
            case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
            case .parseFailed: return "Failed to parse AI response"
            }
        }
    }
}
