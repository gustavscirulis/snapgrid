import Testing
import Foundation
@testable import SnapGrid

@Suite("AI Response Parsing", .tags(.parsing))
struct AIAnalysisParsingTests {

    let service = AIAnalysisService.shared

    // MARK: - parseResponse

    @Test("Valid JSON produces correct AnalysisResult")
    func validJSON() throws {
        let json = """
        {
            "imageContext": "A screenshot of a login form",
            "imageSummary": "Login Form",
            "patterns": [
                {"name": "Text Field", "confidence": 0.95},
                {"name": "Submit Button", "confidence": 0.90}
            ]
        }
        """
        let result = try service.parseResponse(json, provider: "openai", model: "gpt-4o")
        #expect(result.imageContext == "A screenshot of a login form")
        #expect(result.imageSummary == "Login Form")
        #expect(result.patterns.count == 2)
        #expect(result.patterns[0].name == "Text Field")
        #expect(result.provider == "openai")
        #expect(result.model == "gpt-4o")
    }

    @Test("Markdown-fenced JSON is correctly stripped")
    func markdownFencedJSON() throws {
        let fenced = """
        ```json
        {
            "imageContext": "A photo",
            "imageSummary": "Photo",
            "patterns": [{"name": "Sky", "confidence": 0.9}]
        }
        ```
        """
        let result = try service.parseResponse(fenced, provider: "anthropic", model: "claude")
        #expect(result.imageSummary == "Photo")
        #expect(result.patterns.count == 1)
    }

    @Test("Patterns below 0.7 confidence are filtered out")
    func lowConfidenceFiltered() throws {
        let json = """
        {
            "imageContext": "Test",
            "imageSummary": "Test",
            "patterns": [
                {"name": "High", "confidence": 0.95},
                {"name": "Low", "confidence": 0.5},
                {"name": "Border", "confidence": 0.69},
                {"name": "Exact", "confidence": 0.7}
            ]
        }
        """
        let result = try service.parseResponse(json, provider: "openai", model: "gpt-4o")
        #expect(result.patterns.count == 2)
        let names = result.patterns.map(\.name)
        #expect(names.contains("High"))
        #expect(names.contains("Exact"))
        #expect(!names.contains("Low"))
        #expect(!names.contains("Border"))
    }

    @Test("Maximum 6 patterns are kept, sorted by confidence descending")
    func maxSixPatternsSorted() throws {
        let json = """
        {
            "imageContext": "Test",
            "imageSummary": "Test",
            "patterns": [
                {"name": "P1", "confidence": 0.81},
                {"name": "P2", "confidence": 0.82},
                {"name": "P3", "confidence": 0.83},
                {"name": "P4", "confidence": 0.84},
                {"name": "P5", "confidence": 0.85},
                {"name": "P6", "confidence": 0.86},
                {"name": "P7", "confidence": 0.87},
                {"name": "P8", "confidence": 0.88},
                {"name": "P9", "confidence": 0.89},
                {"name": "P10", "confidence": 0.90}
            ]
        }
        """
        let result = try service.parseResponse(json, provider: "openai", model: "gpt-4o")
        #expect(result.patterns.count == 6)
        // Verify descending order
        for i in 0..<(result.patterns.count - 1) {
            #expect(result.patterns[i].confidence >= result.patterns[i + 1].confidence)
        }
        // Verify the top 6 by confidence were kept
        #expect(result.patterns[0].name == "P10")
        #expect(result.patterns[5].name == "P5")
    }

    @Test("Invalid JSON throws a decoding error")
    func invalidJSONThrows() {
        #expect(throws: (any Error).self) {
            try service.parseResponse("not json {{{", provider: "openai", model: "gpt-4o")
        }
    }

    @Test("Provider is correctly set in result",
          arguments: ["openai", "anthropic", "gemini", "openrouter"])
    func parseResponseSetsProvider(_ provider: String) throws {
        let json = """
        {
            "imageContext": "Test",
            "imageSummary": "Test",
            "patterns": [{"name": "Item", "confidence": 0.9}]
        }
        """
        let result = try service.parseResponse(json, provider: provider, model: "test-model")
        #expect(result.provider == provider)
        #expect(result.model == "test-model")
    }

    // MARK: - buildPrompt

    @Test("Build prompt includes custom guidance")
    func buildPromptIncludesGuidance() {
        let prompt = service.buildPrompt(guidance: "Focus on typography")
        #expect(prompt.contains("Focus on typography"))
        #expect(!prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Build prompt falls back to default guidance when nil")
    func buildPromptFallsBackToDefault() {
        let prompt = service.buildPrompt()
        #expect(prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Build prompt falls back to default guidance when empty")
    func buildPromptFallsBackWhenEmpty() {
        let prompt = service.buildPrompt(guidance: "")
        #expect(prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Build prompt appends space context")
    func buildPromptAppendsSpaceContext() {
        let prompt = service.buildPrompt(guidance: "test", spaceContext: "This is a UI collection")
        #expect(prompt.contains("This is a UI collection"))
    }

    // MARK: - isRetryable

    @Test("Retryable HTTP status codes",
          arguments: [429, 502, 503])
    func retryableStatusCodes(_ code: Int) {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: code, message: "error")
        #expect(service.isRetryable(error) == true)
    }

    @Test("Non-retryable HTTP status codes",
          arguments: [400, 401, 403, 404, 500])
    func nonRetryableStatusCodes(_ code: Int) {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: code, message: "error")
        #expect(service.isRetryable(error) == false)
    }

    // MARK: - AIProvider enum properties

    @Test("All providers have non-empty displayName",
          arguments: AIProvider.allCases)
    func providerDisplayName(_ provider: AIProvider) {
        #expect(!provider.displayName.isEmpty)
    }

    @Test("All providers have non-empty defaultModel",
          arguments: AIProvider.allCases)
    func providerDefaultModel(_ provider: AIProvider) {
        #expect(!provider.defaultModel.isEmpty)
    }

    @Test("Provider count is 4")
    func providerCount() {
        #expect(AIProvider.allCases.count == 4)
    }

    @Test("keychainService matches rawValue",
          arguments: AIProvider.allCases)
    func providerKeychainService(_ provider: AIProvider) {
        #expect(provider.keychainService == provider.rawValue)
    }
}
