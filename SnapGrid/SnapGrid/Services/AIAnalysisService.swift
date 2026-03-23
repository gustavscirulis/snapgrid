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

    private let systemPrompt = """
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
    """

    private let userText = "Analyze this image and provide a detailed breakdown of its content. If it's a UI screenshot, focus on UI patterns and components. If it's a general scene, focus on objects and subjects. Respond with a strict, valid JSON object in the format specified in the system prompt. Do not include markdown formatting, explanations, or code block symbols. Use title case for pattern/object names. Provide up to 6 patterns/objects, ordered by confidence."

    private let maxRetries = 2

    func analyze(image: NSImage, provider: AIProvider, model: String, spacePrompt: String? = nil) async throws -> AnalysisResult {
        guard let apiKey = try KeychainService.get(service: provider.keychainService) else {
            throw AnalysisError.noAPIKey
        }

        guard let base64 = Self.imageToBase64(image) else {
            throw AnalysisError.imageConversionFailed
        }

        let prompt = buildPrompt(spacePrompt: spacePrompt)

        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = Double(attempt) * 2.0
                try? await Task.sleep(for: .seconds(delay))
                print("[Analysis] Retry attempt \(attempt)")
            }
            do {
                let responseText: String
                switch provider {
                case .openai:
                    responseText = try await callOpenAI(apiKey: apiKey, model: model, base64Image: base64, prompt: prompt)
                case .anthropic:
                    responseText = try await callAnthropic(apiKey: apiKey, model: model, base64Image: base64, prompt: prompt)
                case .gemini:
                    responseText = try await callGemini(apiKey: apiKey, model: model, base64Image: base64, prompt: prompt)
                case .openrouter:
                    responseText = try await callOpenRouter(apiKey: apiKey, model: model, base64Image: base64, prompt: prompt)
                }
                return try parseResponse(responseText, provider: provider.rawValue, model: model)
            } catch {
                lastError = error
                // Only retry on transient network/server errors
                if !isRetryable(error) { throw error }
            }
        }
        throw lastError!
    }

    private func isRetryable(_ error: Error) -> Bool {
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

    func analyzeVideo(frames: [NSImage], provider: AIProvider, model: String, spacePrompt: String? = nil) async throws -> AnalysisResult {
        // Analyze each frame and merge results
        var allPatterns: [String: [Double]] = [:]
        var contexts: [String] = []
        var summaries: [String] = []

        for frame in frames {
            let result = try await analyze(image: frame, provider: provider, model: model, spacePrompt: spacePrompt)
            contexts.append(result.imageContext)
            summaries.append(result.imageSummary)

            for pattern in result.patterns {
                allPatterns[pattern.name, default: []].append(pattern.confidence)
            }
        }

        // Average confidence per pattern
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
            provider: provider.rawValue,
            model: model
        )
    }

    // MARK: - Provider Implementations

    private func callOpenAI(apiKey: String, model: String, base64Image: String, prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]]
            ],
            "max_completion_tokens": 800
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AnalysisError.invalidResponse
        }
        return content
    }

    private func callAnthropic(apiKey: String, model: String, base64Image: String, prompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
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
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        guard let text = content?.first?["text"] as? String else {
            throw AnalysisError.invalidResponse
        }
        return text
    }

    private func callGemini(apiKey: String, model: String, base64Image: String, prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["parts": [
                    ["text": userText],
                    ["inlineData": [
                        "mimeType": "image/jpeg",
                        "data": base64Image
                    ]]
                ]]
            ],
            "systemInstruction": [
                "parts": [["text": prompt]]
            ],
            "generationConfig": [
                "maxOutputTokens": 800
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        guard let text = parts?.first?["text"] as? String else {
            throw AnalysisError.invalidResponse
        }
        return text
    }

    private func callOpenRouter(apiKey: String, model: String, base64Image: String, prompt: String) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://snapgrid.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("SnapGrid", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]]
            ],
            "max_tokens": 1200
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AnalysisError.invalidResponse
        }
        return content
    }

    // MARK: - Helpers

    private func buildPrompt(spacePrompt: String?) -> String {
        guard let spacePrompt, !spacePrompt.isEmpty else {
            return systemPrompt
        }
        return systemPrompt + "\n\nAdditional instructions:\n" + spacePrompt
    }

    /// Max dimension recommended by Anthropic — larger images are resized server-side anyway.
    static let maxImageDimension: CGFloat = 1568

    static func imageToBase64(_ image: NSImage) -> String? {
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

    private func parseResponse(_ text: String, provider: String, model: String) throws -> AnalysisResult {
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
