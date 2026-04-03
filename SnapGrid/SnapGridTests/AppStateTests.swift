import Testing
import Foundation
import CoreGraphics
@testable import SnapGrid

@Suite("AppState", .tags(.state))
@MainActor
struct AppStateTests {

    // MARK: - ThumbnailSize Column Calculation

    @Test("Small thumbnails: 6 columns at 1200px")
    func smallColumns1200() {
        #expect(ThumbnailSize.small.columns(forWidth: 1200) == 6)
    }

    @Test("Small thumbnails: 5 columns at 1000px")
    func smallColumns1000() {
        #expect(ThumbnailSize.small.columns(forWidth: 1000) == 5)
    }

    @Test("Small thumbnails: 4 columns at 800px")
    func smallColumns800() {
        #expect(ThumbnailSize.small.columns(forWidth: 800) == 4)
    }

    @Test("Small thumbnails: 3 columns at 480px")
    func smallColumns480() {
        #expect(ThumbnailSize.small.columns(forWidth: 480) == 3)
    }

    @Test("Small thumbnails: 2 columns at narrow width")
    func smallColumnsNarrow() {
        #expect(ThumbnailSize.small.columns(forWidth: 300) == 2)
    }

    @Test("Medium thumbnails: 4 columns at 1200px")
    func mediumColumns1200() {
        #expect(ThumbnailSize.medium.columns(forWidth: 1200) == 4)
    }

    @Test("Medium thumbnails: 1 column at narrow width")
    func mediumColumnsNarrow() {
        #expect(ThumbnailSize.medium.columns(forWidth: 400) == 1)
    }

    @Test("Large thumbnails: 3 columns at 1100px")
    func largeColumns1100() {
        #expect(ThumbnailSize.large.columns(forWidth: 1100) == 3)
    }

    @Test("Extra large thumbnails: 2 columns at 700px")
    func extraLargeColumns700() {
        #expect(ThumbnailSize.extraLarge.columns(forWidth: 700) == 2)
    }

    @Test("Extra large thumbnails: 1 column below 700px")
    func extraLargeColumnsNarrow() {
        #expect(ThumbnailSize.extraLarge.columns(forWidth: 699) == 1)
    }

    // MARK: - Range Selection

    @Test("Range select with anchor selects range")
    func rangeSelectWithAnchor() {
        let state = AppState()
        let ids = ["a", "b", "c", "d", "e"]
        state.anchorId = "b"
        state.selectedIds = ["b"]

        state.rangeSelect(targetId: "d", orderedIds: ids)

        #expect(state.selectedIds.contains("b"))
        #expect(state.selectedIds.contains("c"))
        #expect(state.selectedIds.contains("d"))
        #expect(!state.selectedIds.contains("a"))
        #expect(!state.selectedIds.contains("e"))
    }

    @Test("Range select backwards selects range")
    func rangeSelectBackwards() {
        let state = AppState()
        let ids = ["a", "b", "c", "d", "e"]
        state.anchorId = "d"
        state.selectedIds = ["d"]

        state.rangeSelect(targetId: "b", orderedIds: ids)

        #expect(state.selectedIds.contains("b"))
        #expect(state.selectedIds.contains("c"))
        #expect(state.selectedIds.contains("d"))
    }

    @Test("Range select without anchor selects single item")
    func rangeSelectNoAnchor() {
        let state = AppState()
        state.rangeSelect(targetId: "c", orderedIds: ["a", "b", "c", "d"])

        #expect(state.selectedIds == ["c"])
    }

    // MARK: - Undo Stack

    @Test("Push and pop delete batch")
    func undoStack() {
        let state = AppState()
        let batch = [DeletedItemInfo(id: "1", filename: "test.png", mediaType: .image, width: 100, height: 100, duration: nil, spaceId: nil, imageContext: nil, imageSummary: nil, patterns: nil, analyzedAt: nil, analysisProvider: nil, analysisModel: nil)]

        state.pushDeleteBatch(batch)
        let popped = state.popDeleteBatch()

        #expect(popped?.count == 1)
        #expect(popped?[0].id == "1")
    }

    @Test("Undo stack caps at 20 batches")
    func undoStackCap() {
        let state = AppState()
        for i in 0..<25 {
            let batch = [DeletedItemInfo(id: "\(i)", filename: "\(i).png", mediaType: .image, width: 100, height: 100, duration: nil, spaceId: nil, imageContext: nil, imageSummary: nil, patterns: nil, analyzedAt: nil, analysisProvider: nil, analysisModel: nil)]
            state.pushDeleteBatch(batch)
        }

        #expect(state.deletedBatches.count == 20)
        // Oldest batches should have been removed
        #expect(state.deletedBatches.first?[0].id == "5")
    }

    @Test("Pop from empty stack returns nil")
    func popEmptyStack() {
        let state = AppState()
        #expect(state.popDeleteBatch() == nil)
    }

    // MARK: - Zoom

    @Test("Zoom in increases thumbnail size")
    func zoomIn() {
        let state = AppState()
        state.thumbnailSize = .small
        state.zoomIn()
        #expect(state.thumbnailSize == .medium)
    }

    @Test("Zoom in at max stays at max")
    func zoomInAtMax() {
        let state = AppState()
        state.thumbnailSize = .extraLarge
        state.zoomIn()
        #expect(state.thumbnailSize == .extraLarge)
    }

    @Test("Zoom out decreases thumbnail size")
    func zoomOut() {
        let state = AppState()
        state.thumbnailSize = .medium
        state.zoomOut()
        #expect(state.thumbnailSize == .small)
    }

    @Test("Zoom out at min stays at min")
    func zoomOutAtMin() {
        let state = AppState()
        state.thumbnailSize = .small
        state.zoomOut()
        #expect(state.thumbnailSize == .small)
    }
}
