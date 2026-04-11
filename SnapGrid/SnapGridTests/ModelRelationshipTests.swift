import Testing
import Foundation
import SwiftData
@testable import SnapGrid

@Suite("Model Relationships", .tags(.model))
@MainActor
struct ModelRelationshipTests {

    @Test("MediaItem can belong to multiple Spaces")
    func assignToMultipleSpaces() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let primarySpace = Space(name: "UI", order: 0)
        let secondarySpace = Space(name: "Favorites", order: 1)
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(primarySpace)
        context.insert(secondarySpace)
        context.insert(item)
        item.addSpace(primarySpace)
        item.addSpace(secondarySpace)

        try context.save()

        #expect(item.belongs(to: primarySpace.id))
        #expect(item.belongs(to: secondarySpace.id))
        #expect(primarySpace.items.contains(where: { $0.id == item.id }))
        #expect(secondarySpace.items.contains(where: { $0.id == item.id }))
    }

    @Test("AnalysisResult cascades on MediaItem delete")
    func cascadeDelete() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        let analysis = AnalysisResult(
            imageContext: "Test", imageSummary: "Test",
            patterns: [PatternTag(name: "Button", confidence: 0.9)],
            provider: "test", model: "test"
        )
        context.insert(item)
        context.insert(analysis)
        item.analysisResult = analysis

        try context.save()

        let analysisId = analysis.imageContext
        context.delete(item)
        try context.save()

        // AnalysisResult should be gone due to cascade delete rule
        let descriptor = FetchDescriptor<AnalysisResult>()
        let remaining = try context.fetch(descriptor)
        #expect(remaining.isEmpty)
    }

    @Test("Deleting Space removes only that membership")
    func spaceDeleteNullifies() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let removedSpace = Space(name: "Photos", order: 0)
        let keptSpace = Space(name: "Saved", order: 1)
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(removedSpace)
        context.insert(keptSpace)
        context.insert(item)
        item.addSpace(removedSpace)
        item.addSpace(keptSpace)

        try context.save()

        context.delete(removedSpace)
        try context.save()

        #expect(!item.belongs(to: removedSpace.id))
        #expect(item.belongs(to: keptSpace.id))
        #expect(item.orderedSpaceIDs == [keptSpace.id])
    }

    @Test("Multiple items can belong to same Space")
    func multipleItemsInSpace() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let space = Space(name: "UI", order: 0)
        let item1 = MediaItem(mediaType: .image, filename: "a.png", width: 100, height: 100)
        let item2 = MediaItem(mediaType: .image, filename: "b.png", width: 200, height: 200)
        context.insert(space)
        context.insert(item1)
        context.insert(item2)
        item1.addSpace(space)
        item2.addSpace(space)

        try context.save()

        #expect(space.items.count == 2)
    }

    @Test("Space order is stored correctly")
    func spaceOrder() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let space1 = Space(name: "First", order: 0)
        let space2 = Space(name: "Second", order: 1)
        let space3 = Space(name: "Third", order: 2)
        context.insert(space1)
        context.insert(space2)
        context.insert(space3)

        try context.save()

        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)])
        let spaces = try context.fetch(descriptor)
        #expect(spaces.map(\.name) == ["First", "Second", "Third"])
    }
}
