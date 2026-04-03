import Testing
import Foundation
import SwiftData
@testable import SnapGrid

@Suite("Model Relationships", .tags(.model))
@MainActor
struct ModelRelationshipTests {

    @Test("MediaItem can be assigned to a Space")
    func assignToSpace() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let space = Space(name: "UI", order: 0)
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(space)
        context.insert(item)
        item.space = space

        try context.save()

        #expect(item.space?.id == space.id)
        #expect(space.items.contains(where: { $0.id == item.id }))
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

        context.delete(item)
        try context.save()

        let descriptor = FetchDescriptor<AnalysisResult>()
        let remaining = try context.fetch(descriptor)
        #expect(remaining.isEmpty)
    }

    @Test("Deleting Space nullifies MediaItem.space")
    func spaceDeleteNullifies() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let space = Space(name: "Photos", order: 0)
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(space)
        context.insert(item)
        item.space = space

        try context.save()

        context.delete(space)
        try context.save()

        #expect(item.space == nil)
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
        item1.space = space
        item2.space = space

        try context.save()

        #expect(space.items.count == 2)
    }
}
