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
        let batch = [DeletedItemInfo(id: "1", filename: "test.png", mediaType: .image, width: 100, height: 100, duration: nil, spaceIds: [], imageContext: nil, imageSummary: nil, patterns: nil, analyzedAt: nil, analysisProvider: nil, analysisModel: nil)]

        state.pushDeleteBatch(batch)
        guard case .deletion(let items) = state.popUndoBatch() else {
            Issue.record("Expected deletion batch")
            return
        }

        #expect(items.count == 1)
        #expect(items[0].id == "1")
    }

    @Test("Push and pop space change batch")
    func spaceChangeUndoStack() {
        let state = AppState()
        let changes = [SpaceChangeInfo(itemId: "item1", previousSpaceIds: ["spaceA", "spaceB"])]

        state.pushSpaceChangeBatch(changes)
        guard case .spaceChange(let popped) = state.popUndoBatch() else {
            Issue.record("Expected space change batch")
            return
        }

        #expect(popped.count == 1)
        #expect(popped[0].itemId == "item1")
        #expect(popped[0].previousSpaceIds == ["spaceA", "spaceB"])
    }

    @Test("Interleaved undo batches maintain LIFO order")
    func interleavedUndoOrder() {
        let state = AppState()
        state.pushDeleteBatch([DeletedItemInfo(id: "del1", filename: "1.png", mediaType: .image, width: 1, height: 1, duration: nil, spaceIds: [], imageContext: nil, imageSummary: nil, patterns: nil, analyzedAt: nil, analysisProvider: nil, analysisModel: nil)])
        state.pushSpaceChangeBatch([SpaceChangeInfo(itemId: "item1", previousSpaceIds: ["s1"])])
        state.pushDeleteBatch([DeletedItemInfo(id: "del2", filename: "2.png", mediaType: .image, width: 1, height: 1, duration: nil, spaceIds: [], imageContext: nil, imageSummary: nil, patterns: nil, analyzedAt: nil, analysisProvider: nil, analysisModel: nil)])

        guard case .deletion = state.popUndoBatch() else { Issue.record("Expected deletion"); return }
        guard case .spaceChange = state.popUndoBatch() else { Issue.record("Expected space change"); return }
        guard case .deletion = state.popUndoBatch() else { Issue.record("Expected deletion"); return }
        #expect(state.popUndoBatch() == nil)
    }

    @Test("Undo stack caps at 20 batches")
    func undoStackCap() {
        let state = AppState()
        for i in 0..<25 {
            let batch = [DeletedItemInfo(id: "\(i)", filename: "\(i).png", mediaType: .image, width: 100, height: 100, duration: nil, spaceIds: [], imageContext: nil, imageSummary: nil, patterns: nil, analyzedAt: nil, analysisProvider: nil, analysisModel: nil)]
            state.pushDeleteBatch(batch)
        }

        #expect(state.undoStack.count == 20)
        guard case .deletion(let first) = state.undoStack.first else {
            Issue.record("Expected deletion batch")
            return
        }
        #expect(first[0].id == "5")
    }

    @Test("Pop from empty stack returns nil")
    func popEmptyStack() {
        let state = AppState()
        #expect(state.popUndoBatch() == nil)
        #expect(state.popRedoBatch() == nil)
    }

    // MARK: - Redo Stack

    @Test("Push and pop redo batch")
    func redoStack() {
        let state = AppState()
        let changes = [SpaceChangeInfo(itemId: "item1", previousSpaceIds: ["s1"])]
        state.pushRedoBatch(.spaceChange(changes))

        guard case .spaceChange(let popped) = state.popRedoBatch() else {
            Issue.record("Expected space change batch")
            return
        }
        #expect(popped.count == 1)
        #expect(popped[0].itemId == "item1")
    }

    @Test("New action clears redo stack")
    func newActionClearsRedo() {
        let state = AppState()
        state.pushRedoBatch(.spaceChange([SpaceChangeInfo(itemId: "item1", previousSpaceIds: ["s1"])]))
        #expect(state.redoStack.count == 1)

        state.pushSpaceChangeBatch([SpaceChangeInfo(itemId: "item2", previousSpaceIds: ["s2"])])
        #expect(state.redoStack.isEmpty)
    }

    @Test("Redo stack caps at 20 batches")
    func redoStackCap() {
        let state = AppState()
        for i in 0..<25 {
            state.pushRedoBatch(.spaceChange([SpaceChangeInfo(itemId: "\(i)", previousSpaceIds: [])]))
        }
        #expect(state.redoStack.count == 20)
    }

    @Test("Push and pop space deletion batch")
    func spaceDeletionUndoStack() {
        let state = AppState()
        let info = DeletedSpaceInfo(id: "s1", name: "Design", order: 0, createdAt: .now, customPrompt: "Analyze design", useCustomPrompt: true, itemIds: ["item1", "item2"])
        state.pushUndoBatch(.spaceDeletion(info))

        guard case .spaceDeletion(let popped) = state.popUndoBatch() else {
            Issue.record("Expected space deletion batch")
            return
        }
        #expect(popped.id == "s1")
        #expect(popped.name == "Design")
        #expect(popped.itemIds == ["item1", "item2"])
        #expect(popped.customPrompt == "Analyze design")
        #expect(popped.useCustomPrompt == true)
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
