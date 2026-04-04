import Testing
import SwiftData
@testable import SnapGrid

/// Integration tests for iOS SyncService: sidecar files on disk → SwiftData state.
/// Every test uses its own unique temp directory — safe for parallel execution.
@Suite(.tags(.integration, .sync))
struct SyncServiceIntegrationTests {
    let tempRoot: URL
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        tempRoot = try IntegrationTestSupport.makeTempRoot()
        container = try TestContainer.create()
        context = ModelContext(container)
    }


    // MARK: - New Item Import

    @Test("Sidecar + media file creates MediaItem with correct fields")
    @MainActor func syncImportsNewItemFromSidecar() async throws {
        let sidecar = IntegrationTestSupport.makeSidecar(id: "test-1", width: 1920, height: 1080)
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "test-1", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == "test-1")
        #expect(item.width == 1920)
        #expect(item.height == 1080)
        #expect(item.mediaType == .image)
        #expect(item.filename == "test-1.png")
    }

    @Test("Sidecar without media file is skipped (orphan guard)")
    @MainActor func syncSkipsSidecarWithNoMediaFile() async throws {
        let sidecar = IntegrationTestSupport.makeSidecar(id: "orphan-1")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        // No media file created

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.isEmpty)
    }

    @Test("Sidecar with analysis fields creates AnalysisResult")
    @MainActor func syncImportsAnalysisResult() async throws {
        let sidecar = IntegrationTestSupport.makeSidecar(
            id: "analyzed-1",
            imageContext: "A dashboard showing metrics",
            imageSummary: "Metrics dashboard",
            patterns: [SidecarPattern(name: "dashboard", confidence: 0.95)],
            analyzedAt: Date()
        )
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "analyzed-1", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)
        let result = try #require(item.analysisResult)
        #expect(result.imageContext == "A dashboard showing metrics")
        #expect(result.imageSummary == "Metrics dashboard")
        #expect(result.patterns.count == 1)
        #expect(result.patterns.first?.name == "dashboard")
        #expect(result.provider == "synced")
    }

    @Test("Sidecar with spaceId assigns Space to new item")
    @MainActor func syncAssignsSpaceToNewItem() async throws {
        let space = Space(id: "sp-1", name: "Screenshots", order: 0)
        context.insert(space)
        context.saveOrLog()

        let sidecar = IntegrationTestSupport.makeSidecar(id: "spaced-1", spaceId: "sp-1")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "spaced-1", in: tempRoot)

        // Write spaces.json so syncSpaces creates the space
        let spacesFile = SidecarSpacesFile(
            spaces: [SidecarSpace(id: "sp-1", name: "Screenshots", order: 0, createdAt: Date(), customPrompt: nil, useCustomPrompt: false)],
            allSpaceGuidance: nil,
            useAllSpaceGuidance: false
        )
        try IntegrationTestSupport.writeSpacesJSON(spacesFile, to: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)
        #expect(item.space?.id == "sp-1")
    }

    // MARK: - Update Existing Items

    @Test("Updates space assignment on existing item")
    @MainActor func syncUpdatesSpaceOnExistingItem() async throws {
        // Create existing item with no space
        let item = MediaItem(id: "update-1", mediaType: .image, filename: "update-1.png", width: 800, height: 600)
        context.insert(item)

        let space = Space(id: "sp-2", name: "Designs", order: 1)
        context.insert(space)
        context.saveOrLog()

        // Write sidecar assigning it to space
        let sidecar = IntegrationTestSupport.makeSidecar(id: "update-1", spaceId: "sp-2")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "update-1", in: tempRoot)

        let spacesFile = SidecarSpacesFile(
            spaces: [SidecarSpace(id: "sp-2", name: "Designs", order: 1, createdAt: Date(), customPrompt: nil, useCustomPrompt: false)],
            allSpaceGuidance: nil,
            useAllSpaceGuidance: false
        )
        try IntegrationTestSupport.writeSpacesJSON(spacesFile, to: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(item.space?.id == "sp-2")
    }

    @Test("Removes space when sidecar has nil spaceId")
    @MainActor func syncRemovesSpaceWhenSidecarHasNilSpaceId() async throws {
        let space = Space(id: "sp-3", name: "Old Space", order: 0)
        context.insert(space)

        let item = MediaItem(id: "unspace-1", mediaType: .image, filename: "unspace-1.png", width: 800, height: 600)
        item.space = space
        context.insert(item)
        context.saveOrLog()

        // Sidecar with no spaceId
        let sidecar = IntegrationTestSupport.makeSidecar(id: "unspace-1", spaceId: nil)
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "unspace-1", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(item.space == nil)
    }

    @Test("Updates analysis when remote is newer")
    @MainActor func syncUpdatesAnalysisWhenRemoteIsNewer() async throws {
        let oldDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let newDate = Date()

        let item = MediaItem(id: "analysis-update-1", mediaType: .image, filename: "analysis-update-1.png", width: 800, height: 600)
        item.analysisResult = AnalysisResult(
            imageContext: "Old analysis",
            imageSummary: "Old summary",
            patterns: [],
            analyzedAt: oldDate,
            provider: "synced",
            model: "old"
        )
        context.insert(item)
        context.saveOrLog()

        let sidecar = IntegrationTestSupport.makeSidecar(
            id: "analysis-update-1",
            imageContext: "New analysis from Mac",
            imageSummary: "New summary",
            patterns: [SidecarPattern(name: "updated", confidence: 0.9)],
            analyzedAt: newDate
        )
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "analysis-update-1", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(item.analysisResult?.imageContext == "New analysis from Mac")
        #expect(item.analysisResult?.patterns.count == 1)
    }

    @Test("Keeps local analysis when it's newer than remote")
    @MainActor func syncKeepsLocalAnalysisWhenNewer() async throws {
        let newerDate = Date()
        let olderDate = Date(timeIntervalSinceNow: -3600)

        let item = MediaItem(id: "keep-local-1", mediaType: .image, filename: "keep-local-1.png", width: 800, height: 600)
        item.analysisResult = AnalysisResult(
            imageContext: "Local analysis (newer)",
            imageSummary: "Local summary",
            patterns: [],
            analyzedAt: newerDate,
            provider: "openai",
            model: "gpt-4o"
        )
        context.insert(item)
        context.saveOrLog()

        let sidecar = IntegrationTestSupport.makeSidecar(
            id: "keep-local-1",
            imageContext: "Remote analysis (older)",
            imageSummary: "Remote summary",
            analyzedAt: olderDate
        )
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "keep-local-1", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(item.analysisResult?.imageContext == "Local analysis (newer)")
        #expect(item.analysisResult?.provider == "openai")
    }

    @Test("Sets sourceURL when item has nil")
    @MainActor func syncSetsSourceURLWhenNil() async throws {
        let item = MediaItem(id: "source-1", mediaType: .image, filename: "source-1.png", width: 800, height: 600)
        context.insert(item)
        context.saveOrLog()

        let sidecar = IntegrationTestSupport.makeSidecar(id: "source-1", sourceURL: "https://x.com/user/status/123")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "source-1", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(item.sourceURL == "https://x.com/user/status/123")
    }

    @Test("Preserves existing sourceURL even when sidecar has different one")
    @MainActor func syncPreservesExistingSourceURL() async throws {
        let item = MediaItem(id: "source-2", mediaType: .image, filename: "source-2.png", width: 800, height: 600)
        item.sourceURL = "https://original.com/image.png"
        context.insert(item)
        context.saveOrLog()

        let sidecar = IntegrationTestSupport.makeSidecar(id: "source-2", sourceURL: "https://different.com/image.png")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)
        try IntegrationTestSupport.createDummyMedia(id: "source-2", in: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(item.sourceURL == "https://original.com/image.png")
    }

    // MARK: - Deletion

    @Test("Deletes orphaned SwiftData items when sidecar is missing")
    @MainActor func syncDeletesOrphanedItems() async throws {
        let item = MediaItem(id: "orphan-db-1", mediaType: .image, filename: "orphan-db-1.png", width: 800, height: 600)
        context.insert(item)
        context.saveOrLog()

        // Don't write any sidecar — item should be removed as orphaned

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.isEmpty)
    }

    // MARK: - Spaces

    @Test("Imports spaces from spaces.json")
    @MainActor func syncImportsSpacesFromJSON() async throws {
        let spacesFile = SidecarSpacesFile(
            spaces: [
                SidecarSpace(id: "sp-a", name: "Screenshots", order: 0, createdAt: Date(), customPrompt: nil, useCustomPrompt: false),
                SidecarSpace(id: "sp-b", name: "Designs", order: 1, createdAt: Date(), customPrompt: "Focus on layout", useCustomPrompt: true)
            ],
            allSpaceGuidance: nil,
            useAllSpaceGuidance: false
        )
        try IntegrationTestSupport.writeSpacesJSON(spacesFile, to: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let spaces = try context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)]))
        #expect(spaces.count == 2)
        #expect(spaces[0].name == "Screenshots")
        #expect(spaces[1].name == "Designs")
        #expect(spaces[1].customPrompt == "Focus on layout")
        #expect(spaces[1].useCustomPrompt == true)
    }

    @Test("Deletes spaces not present in spaces.json")
    @MainActor func syncDeletesRemovedSpaces() async throws {
        let keep = Space(id: "sp-keep", name: "Keep Me", order: 0)
        let remove = Space(id: "sp-remove", name: "Remove Me", order: 1)
        context.insert(keep)
        context.insert(remove)
        context.saveOrLog()

        let spacesFile = SidecarSpacesFile(
            spaces: [SidecarSpace(id: "sp-keep", name: "Keep Me", order: 0, createdAt: Date(), customPrompt: nil, useCustomPrompt: false)],
            allSpaceGuidance: nil,
            useAllSpaceGuidance: false
        )
        try IntegrationTestSupport.writeSpacesJSON(spacesFile, to: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let spaces = try context.fetch(FetchDescriptor<Space>())
        #expect(spaces.count == 1)
        #expect(spaces.first?.id == "sp-keep")
    }

    @Test("Imports all-space guidance from spaces.json to UserDefaults")
    @MainActor func syncImportsGuidanceFromSpacesJSON() async throws {
        defer {
            UserDefaults.standard.removeObject(forKey: "allSpacePrompt")
            UserDefaults.standard.removeObject(forKey: "useAllSpacePrompt")
        }

        let spacesFile = SidecarSpacesFile(
            spaces: [],
            allSpaceGuidance: "Focus on accessibility patterns",
            useAllSpaceGuidance: true
        )
        try IntegrationTestSupport.writeSpacesJSON(spacesFile, to: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        #expect(UserDefaults.standard.string(forKey: "allSpacePrompt") == "Focus on accessibility patterns")
        #expect(UserDefaults.standard.bool(forKey: "useAllSpacePrompt") == true)
    }

    @Test("Handles legacy bare-array spaces.json format")
    @MainActor func syncHandlesLegacyBareArrayFormat() async throws {
        let spaces = [
            SidecarSpace(id: "legacy-1", name: "Legacy Space", order: 0, createdAt: Date(), customPrompt: nil, useCustomPrompt: false)
        ]
        try IntegrationTestSupport.writeLegacySpacesJSON(spaces, to: tempRoot)

        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let result = try context.fetch(FetchDescriptor<Space>())
        #expect(result.count == 1)
        #expect(result.first?.name == "Legacy Space")
    }
}
