import Foundation

struct DiscoveredModel: Identifiable, Sendable {
    let id: String
    let displayName: String
}

final class ModelDiscoveryService: @unchecked Sendable {
    static let shared = ModelDiscoveryService()
    static let autoModelValue = "auto"

    private var cache: [AIProvider: [DiscoveredModel]] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    private func getCached(for provider: AIProvider) -> [DiscoveredModel]? {
        lock.lock()
        defer { lock.unlock() }
        return cache[provider]
    }

    private func setCached(_ models: [DiscoveredModel], for provider: AIProvider) {
        lock.lock()
        defer { lock.unlock() }
        cache[provider] = models
    }

    func fetchModels(for provider: AIProvider) async throws -> [DiscoveredModel] {
        if let cached = getCached(for: provider) {
            return cached
        }

        guard let apiKey = try KeychainService.get(service: provider.keychainService) else {
            throw DiscoveryError.noAPIKey
        }

        let models: [DiscoveredModel]
        switch provider {
        case .openai:
            models = try await fetchOpenAIModels(apiKey: apiKey)
        case .anthropic:
            models = try await fetchAnthropicModels(apiKey: apiKey)
        case .gemini:
            models = try await fetchGeminiModels(apiKey: apiKey)
        case .openrouter:
            models = try await fetchOpenRouterModels(apiKey: apiKey)
        }

        setCached(models, for: provider)
        return models
    }

    func resolveAutoModel(for provider: AIProvider) async -> String {
        do {
            let models = try await fetchModels(for: provider)
            return models.first?.id ?? provider.defaultModel
        } catch {
            return provider.defaultModel
        }
    }

    func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    func clearCache(for provider: AIProvider) {
        lock.lock()
        cache.removeValue(forKey: provider)
        lock.unlock()
    }

    // MARK: - OpenAI

    private let visionPrefixes = ["gpt-4o", "gpt-4.1", "gpt-5"]
    private let excludedPatterns = [
        "embedding", "tts", "whisper", "dall-e", "davinci", "babbage",
        "moderation", "realtime", "transcribe", "audio", "search",
        "codex", "codecs", "image", "preview"
    ]
    private let dateSnapshotRegex = try! NSRegularExpression(pattern: "\\d{4}-?\\d{2}-?\\d{2}")

    func isOpenAIVisionCapable(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        if excludedPatterns.contains(where: { lower.contains($0) }) { return false }
        if hasDateSnapshot(lower) { return false }
        return visionPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    func openAIScore(_ modelId: String) -> Int {
        let lower = modelId.lowercased()
        var score = 0
        if lower.hasPrefix("gpt-5") {
            score = 5000
            if let match = lower.range(of: "gpt-5\\.(\\d+)", options: .regularExpression),
               let digit = Int(String(lower[match].dropFirst(5))) {
                score += digit * 100
            }
        } else if lower.hasPrefix("gpt-4.1") {
            score = 4100
        } else if lower.hasPrefix("gpt-4o") {
            score = 4050
        }
        if lower.contains("-nano") { score -= 20 }
        else if lower.contains("-mini") { score -= 10 }
        return score
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []

        return models
            .compactMap { $0["id"] as? String }
            .filter { isOpenAIVisionCapable($0) }
            .sorted { openAIScore($0) > openAIScore($1) }
            .map { DiscoveredModel(id: $0, displayName: $0) }
    }

    // MARK: - Anthropic

    func isAnthropicVisionCapable(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        guard lower.hasPrefix("claude-") else { return false }
        return !hasDateSnapshot(lower)
    }

    func anthropicScore(_ modelId: String) -> Int {
        let lower = modelId.lowercased()
        var score = 0

        // Version: "claude-sonnet-4-5" → 4.5 * 1000
        if let match = lower.range(of: "claude-\\w+-(\\d+)-(\\d+)", options: .regularExpression) {
            let segment = String(lower[match])
            let parts = segment.split(separator: "-")
            if parts.count >= 4, let major = Int(parts[2]), let minor = Int(parts[3]) {
                score += (major * 10 + minor) * 100
            }
        }

        if lower.contains("sonnet") { score += 300 }
        else if lower.contains("opus") { score += 200 }
        else if lower.contains("haiku") { score += 100 }

        return score
    }

    private func fetchAnthropicModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []

        return models
            .compactMap { dict -> (String, String)? in
                guard let id = dict["id"] as? String else { return nil }
                let display = dict["display_name"] as? String ?? id
                return (id, display)
            }
            .filter { isAnthropicVisionCapable($0.0) }
            .sorted { anthropicScore($0.0) > anthropicScore($1.0) }
            .map { DiscoveredModel(id: $0.0, displayName: $0.1) }
    }

    // MARK: - Gemini

    private let geminiExcluded = ["embedding", "aqa", "text", "tuning"]

    func isGeminiVisionCapable(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        guard lower.contains("gemini") else { return false }
        if geminiExcluded.contains(where: { lower.contains($0) }) { return false }
        return !hasDateSnapshot(lower)
    }

    func geminiScore(_ modelId: String) -> Int {
        let lower = modelId.lowercased()
        var score = 0

        if let match = lower.range(of: "gemini-(\\d+)\\.(\\d+)", options: .regularExpression) {
            let segment = String(lower[match])
            let parts = segment.split(separator: "-")[1].split(separator: ".")
            if parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) {
                score += (major * 10 + minor) * 100
            }
        }

        if lower.contains("pro") { score += 50 }
        else if lower.contains("flash") { score += 30 }

        return score
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        let request = URLRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []

        return models
            .compactMap { dict -> (String, String)? in
                guard let name = dict["name"] as? String else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                let display = dict["displayName"] as? String ?? id
                return (id, display)
            }
            .filter { isGeminiVisionCapable($0.0) }
            .sorted { geminiScore($0.0) > geminiScore($1.0) }
            .map { DiscoveredModel(id: $0.0, displayName: $0.1) }
    }

    // MARK: - OpenRouter

    private func fetchOpenRouterModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []

        return models
            .compactMap { dict -> DiscoveredModel? in
                guard let id = dict["id"] as? String else { return nil }
                let arch = dict["architecture"] as? [String: Any]
                let modalities = arch?["input_modalities"] as? [String] ?? []
                guard modalities.contains("image") else { return nil }
                let display = dict["name"] as? String ?? id
                return DiscoveredModel(id: id, displayName: display)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Helpers

    func hasDateSnapshot(_ lowercased: String) -> Bool {
        let range = NSRange(lowercased.startIndex..., in: lowercased)
        return dateSnapshotRegex.firstMatch(in: lowercased, range: range) != nil
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DiscoveryError.apiError(body)
        }
    }

    enum DiscoveryError: LocalizedError {
        case noAPIKey
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured"
            case .apiError(let msg): return "API error: \(msg)"
            }
        }
    }
}
