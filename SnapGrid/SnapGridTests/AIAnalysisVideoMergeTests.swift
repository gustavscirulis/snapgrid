import Testing
import Foundation
@testable import SnapGrid

@Suite("Video Frame Merge Algorithm", .tags(.parsing))
struct AIAnalysisVideoMergeTests {

    @Test("Two frames with overlapping patterns averages confidence")
    func overlappingPatternsAveraged() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: [
                "Button": [0.9, 0.8],    // avg = 0.85
                "Header": [1.0, 0.9],    // avg = 0.95
            ],
            contexts: ["Frame 1 context", "Frame 2 context"],
            summaries: ["Summary1", "Summary2"],
            provider: "test",
            model: "test"
        )

        let buttonPattern = result.patterns.first(where: { $0.name == "Button" })
        #expect(buttonPattern != nil)
        #expect(abs(buttonPattern!.confidence - 0.85) < 0.001)

        let headerPattern = result.patterns.first(where: { $0.name == "Header" })
        #expect(abs(headerPattern!.confidence - 0.95) < 0.001)
    }

    @Test("Pattern below 0.7 after averaging is filtered out")
    func lowAverageFiltered() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: [
                "Faint": [0.8, 0.5],     // avg = 0.65 → filtered
                "Strong": [0.9, 0.9],    // avg = 0.9 → kept
            ],
            contexts: ["c1", "c2"],
            summaries: ["s1"],
            provider: "test",
            model: "test"
        )

        #expect(result.patterns.count == 1)
        #expect(result.patterns[0].name == "Strong")
    }

    @Test("More than 10 unique patterns are capped")
    func cappedAtTen() {
        var patterns: [String: [Double]] = [:]
        for i in 1...15 {
            patterns["Pattern\(i)"] = [0.8 + Double(i) * 0.005]
        }

        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: patterns,
            contexts: ["ctx"],
            summaries: ["sum"],
            provider: "test",
            model: "test"
        )

        #expect(result.patterns.count == 10)
    }

    @Test("Patterns sorted by confidence descending")
    func sortedDescending() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: [
                "Low": [0.75],
                "High": [0.95],
                "Mid": [0.85],
            ],
            contexts: ["ctx"],
            summaries: ["sum"],
            provider: "test",
            model: "test"
        )

        #expect(result.patterns[0].name == "High")
        #expect(result.patterns[1].name == "Mid")
        #expect(result.patterns[2].name == "Low")
    }

    @Test("Contexts joined with double newline")
    func contextsJoined() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: ["A": [0.9]],
            contexts: ["First frame", "Second frame"],
            summaries: ["Video"],
            provider: "test",
            model: "test"
        )

        #expect(result.imageContext == "First frame\n\nSecond frame")
    }

    @Test("Summary uses first frame's summary")
    func firstSummaryUsed() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: ["A": [0.9]],
            contexts: ["ctx"],
            summaries: ["First", "Second"],
            provider: "test",
            model: "test"
        )

        #expect(result.imageSummary == "First")
    }

    @Test("Empty summaries defaults to Video")
    func emptySummariesDefault() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: ["A": [0.9]],
            contexts: ["ctx"],
            summaries: [],
            provider: "test",
            model: "test"
        )

        #expect(result.imageSummary == "Video")
    }

    @Test("Non-overlapping patterns all kept")
    func nonOverlappingKept() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: [
                "Button": [0.9],
                "Header": [0.85],
                "Footer": [0.8],
            ],
            contexts: ["ctx"],
            summaries: ["sum"],
            provider: "test",
            model: "test"
        )

        #expect(result.patterns.count == 3)
    }

    @Test("Provider and model passed through")
    func providerModelPassthrough() {
        let result = AIAnalysisService.mergeFrameResults(
            allPatterns: ["A": [0.9]],
            contexts: ["ctx"],
            summaries: ["sum"],
            provider: "anthropic",
            model: "claude-sonnet-4-5"
        )

        #expect(result.provider == "anthropic")
        #expect(result.model == "claude-sonnet-4-5")
    }
}
