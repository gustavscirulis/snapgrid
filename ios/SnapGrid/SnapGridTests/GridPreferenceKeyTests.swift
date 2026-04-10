import Testing
import SwiftUI
@testable import SnapGrid

@Suite("GridItemRectsPreferenceKey", .tags(.layout))
@MainActor
struct GridPreferenceKeyTests {

    // MARK: - Reduce logic

    @Test("Reduce merges frames from multiple sources")
    func reduceMerges() {
        var value: [String: CGRect] = ["a": CGRect(x: 0, y: 0, width: 100, height: 100)]
        GridItemRectsPreferenceKey.reduce(value: &value) {
            ["b": CGRect(x: 100, y: 0, width: 100, height: 100)]
        }
        #expect(value.count == 2)
        #expect(value["a"] != nil)
        #expect(value["b"] != nil)
    }

    @Test("Reduce does not clear existing frames when next value is empty")
    func reduceEmptyDoesNotClear() {
        // This is the exact regression guard: if a child view emits an empty
        // dictionary (e.g. because frame tracking was gated off), existing
        // entries must survive. The hero dismiss animation depends on this.
        var value: [String: CGRect] = [
            "item1": CGRect(x: 10, y: 20, width: 180, height: 240),
            "item2": CGRect(x: 200, y: 20, width: 180, height: 300)
        ]
        GridItemRectsPreferenceKey.reduce(value: &value) { [:] }
        #expect(value.count == 2, "Empty child emission must not erase existing item frames")
        #expect(value["item1"] != nil)
        #expect(value["item2"] != nil)
    }

    @Test("Reduce prefers on-screen frames over off-screen when same key exists")
    func reduceOnScreenPreferred() {
        let screen = UIScreen.main.bounds
        let onScreen = CGRect(
            x: screen.midX - 50, y: screen.midY - 50,
            width: 100, height: 100
        )
        let offScreen = CGRect(x: -500, y: -500, width: 100, height: 100)

        // Existing has off-screen frame, next provides on-screen for same key
        var value: [String: CGRect] = ["item": offScreen]
        GridItemRectsPreferenceKey.reduce(value: &value) { ["item": onScreen] }
        #expect(value["item"] == onScreen, "On-screen frame should replace off-screen one")
    }

    @Test("Reduce keeps existing on-screen frame when next value is off-screen")
    func reduceKeepsExistingOnScreen() {
        let screen = UIScreen.main.bounds
        let onScreen = CGRect(
            x: screen.midX - 50, y: screen.midY - 50,
            width: 100, height: 100
        )
        let offScreen = CGRect(x: -500, y: -500, width: 100, height: 100)

        var value: [String: CGRect] = ["item": onScreen]
        GridItemRectsPreferenceKey.reduce(value: &value) { ["item": offScreen] }
        #expect(value["item"] == onScreen, "Existing on-screen frame should be kept")
    }
}

@Suite("DetailChrome", .tags(.layout))
@MainActor
struct DetailChromeTests {

    @Test("Toolbar title prefers current item summary and falls back when missing")
    func toolbarTitlePrefersSummary() {
        let summarized = MediaItem(mediaType: .image, filename: "a.jpg", width: 100, height: 100)
        summarized.analysisResult = AnalysisResult(
            imageContext: "Context",
            imageSummary: "Hero Shot",
            patterns: [],
            provider: "test",
            model: "test"
        )

        let untitled = MediaItem(mediaType: .image, filename: "b.jpg", width: 100, height: 100)

        #expect(
            DetailChrome.toolbarTitle(
                currentItemId: summarized.id,
                items: [summarized, untitled],
                fallback: "All media"
            ) == "Hero Shot"
        )

        #expect(
            DetailChrome.toolbarTitle(
                currentItemId: untitled.id,
                items: [summarized, untitled],
                fallback: "All media"
            ) == "All media"
        )
    }

    @Test("Detail mode hides top actions and tab bar")
    func detailModeVisibilityRules() {
        #expect(DetailChrome.showsTopBarActions(isDetailPresented: false))
        #expect(!DetailChrome.showsTopBarActions(isDetailPresented: true))
        #expect(!DetailChrome.hidesTabBar(isDetailPresented: false))
        #expect(DetailChrome.hidesTabBar(isDetailPresented: true))
    }

    @Test("Reserved top inset includes safe area and toolbar spacing")
    func reservedTopInsetAddsToolbarClearance() {
        let inset = DetailChrome.reservedTopInset(safeAreaTop: 59)
        #expect(inset == 59 + DetailChrome.navigationBarHeight + DetailChrome.mediaTopPadding)
    }
}
