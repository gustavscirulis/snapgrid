import Testing
@testable import SnapGrid

@Suite("AppState", .tags(.model))
@MainActor
struct AppStateTests {

    @Test("Pattern search is queued until overlay close")
    func queuePatternSearchDefersMutation() {
        let state = AppState()
        state.searchText = "existing"

        state.queuePatternSearch("Button")

        #expect(state.searchText == "existing")
        #expect(state.pendingSearchActivation)
        #expect(state.pendingSearchPattern == "Button")
    }

    @Test("Queued pattern search falls back to all tab before iOS 26")
    func applyPendingSearchFallsBackToAllTab() {
        let state = AppState()
        state.selectedTab = .spaces
        state.queuePatternSearch("Button")

        state.applyPendingSearchIfNeeded(prefersDedicatedSearchTab: false)

        #expect(state.searchText == "Button")
        #expect(state.selectedTab == .all)
        #expect(!state.pendingSearchActivation)
        #expect(state.pendingSearchPattern == nil)
    }

    @Test("Queued pattern search can activate dedicated search tab")
    func applyPendingSearchActivatesSearchTab() {
        let state = AppState()
        state.selectedTab = .all
        state.queuePatternSearch("Chart")

        state.applyPendingSearchIfNeeded(prefersDedicatedSearchTab: true)

        #expect(state.searchText == "Chart")
        #expect(state.selectedTab == .search)
        #expect(!state.pendingSearchActivation)
        #expect(state.pendingSearchPattern == nil)
    }
}
