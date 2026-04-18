import Testing
import Foundation
@testable import SnapGrid

/// Tests for the AI guidance resolution chain introduced in PR #132.
/// The chain is: space custom prompt → all-space guidance → default guidance.
@Suite("Guidance Fallback Chain", .tags(.parsing))
struct GuidanceFallbackTests {

    let service = AIAnalysisService.shared

    // MARK: - buildPrompt guidance fallback

    @Test("Custom guidance overrides default")
    func customGuidanceOverridesDefault() {
        let prompt = service.buildPrompt(guidance: "Focus on typography")
        #expect(prompt.contains("Focus on typography"))
        #expect(!prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Nil guidance falls back to default")
    func nilGuidanceFallsToDefault() {
        let prompt = service.buildPrompt(guidance: nil)
        #expect(prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Empty string guidance falls back to default")
    func emptyGuidanceFallsToDefault() {
        let prompt = service.buildPrompt(guidance: "")
        #expect(prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Space context appended after guidance")
    func spaceContextAppended() {
        let prompt = service.buildPrompt(guidance: "Test", spaceContext: "Collection: UI Screenshots")
        #expect(prompt.contains("Test"))
        #expect(prompt.contains("Collection: UI Screenshots"))
    }

    @Test("Empty space context not appended")
    func emptySpaceContextIgnored() {
        let prompt1 = service.buildPrompt(guidance: "Test", spaceContext: "")
        let prompt2 = service.buildPrompt(guidance: "Test", spaceContext: nil)
        // Both should produce the same prompt without trailing context
        #expect(prompt1 == prompt2)
    }

    @Test("Prompt always contains system prompt")
    func alwaysContainsSystemPrompt() {
        let prompt = service.buildPrompt(guidance: "custom", spaceContext: "context")
        #expect(prompt.contains("expert image analyst"))
        #expect(prompt.contains("imageContext"))
        #expect(prompt.contains("imageSummary"))
    }

    @Test("Prompt structure: system + analysis_focus + context in order")
    func promptStructure() {
        let prompt = service.buildPrompt(guidance: "CUSTOM_GUIDANCE", spaceContext: "SPACE_CONTEXT")
        let focusIndex = prompt.range(of: "<analysis_focus>")!.lowerBound
        let guidanceIndex = prompt.range(of: "CUSTOM_GUIDANCE")!.lowerBound
        let contextIndex = prompt.range(of: "SPACE_CONTEXT")!.lowerBound
        #expect(focusIndex < guidanceIndex)
        #expect(guidanceIndex < contextIndex)
    }
}
