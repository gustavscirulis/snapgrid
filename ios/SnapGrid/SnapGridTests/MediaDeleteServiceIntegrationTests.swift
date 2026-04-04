import Testing
import SwiftData
import Foundation
@testable import SnapGrid

/// Integration tests for iOS MediaDeleteService trash operations.
/// Verifies move-to-trash, rollback, old-trash cleanup, and trash→sync interaction.
@Suite(.tags(.integration, .filesystem))
struct MediaDeleteServiceIntegrationTests {
    let tempRoot: URL
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        tempRoot = try IntegrationTestSupport.makeTempRoot()
        container = try TestContainer.create()
        context = ModelContext(container)
    }


    // MARK: - Move to Trash

    @Test("Moves image, sidecar, and thumbnail to .trash/ subdirs")
    func moveToTrashMovesAllThreeFiles() throws {
        // Create all three files
        try IntegrationTestSupport.createDummyMedia(id: "trash-1", in: tempRoot)
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "trash-1"), to: tempRoot)
        try IntegrationTestSupport.createDummyThumbnail(id: "trash-1", in: tempRoot)

        try MediaDeleteService.moveToTrash(filename: "trash-1.png", id: "trash-1", rootURL: tempRoot)

        let fm = FileManager.default
        // Original files should be gone
        #expect(!fm.fileExists(atPath: tempRoot.appendingPathComponent("images/trash-1.png").path))
        #expect(!fm.fileExists(atPath: tempRoot.appendingPathComponent("metadata/trash-1.json").path))
        #expect(!fm.fileExists(atPath: tempRoot.appendingPathComponent("thumbnails/trash-1.jpg").path))

        // Trash files should exist
        #expect(fm.fileExists(atPath: tempRoot.appendingPathComponent(".trash/images/trash-1.png").path))
        #expect(fm.fileExists(atPath: tempRoot.appendingPathComponent(".trash/metadata/trash-1.json").path))
        #expect(fm.fileExists(atPath: tempRoot.appendingPathComponent(".trash/thumbnails/trash-1.jpg").path))
    }

    @Test("Handles missing files gracefully (only image exists)")
    func moveToTrashHandlesMissingFiles() throws {
        // Only create the image file — no sidecar, no thumbnail
        try IntegrationTestSupport.createDummyMedia(id: "partial-1", in: tempRoot)

        try MediaDeleteService.moveToTrash(filename: "partial-1.png", id: "partial-1", rootURL: tempRoot)

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: tempRoot.appendingPathComponent("images/partial-1.png").path))
        #expect(fm.fileExists(atPath: tempRoot.appendingPathComponent(".trash/images/partial-1.png").path))
    }

    @Test("Replaces existing file in trash with same name")
    func moveToTrashReplacesExistingInTrash() throws {
        // Put a file in trash first
        let trashImageURL = tempRoot.appendingPathComponent(".trash/images/replace-1.png")
        try Data([0x01]).write(to: trashImageURL)

        // Create new file with same name
        try IntegrationTestSupport.createDummyMedia(id: "replace-1", in: tempRoot)

        // Should not throw — replaces the existing trash file
        try MediaDeleteService.moveToTrash(filename: "replace-1.png", id: "replace-1", rootURL: tempRoot)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: trashImageURL.path))
        // Verify it's the new file (PNG data is larger than our 1-byte placeholder)
        let data = try Data(contentsOf: trashImageURL)
        #expect(data.count > 1)
    }

    // MARK: - Old Trash Cleanup

    @Test("emptyOldTrash removes old files but keeps recent ones")
    func emptyOldTrashRemovesOldFiles() throws {
        let fm = FileManager.default

        // Create an "old" file in trash — set its modification date to 31 days ago
        let oldFileURL = tempRoot.appendingPathComponent(".trash/images/old-1.png")
        try IntegrationTestSupport.dummyPNGData.write(to: oldFileURL)
        let oldDate = Date(timeIntervalSinceNow: -31 * 24 * 3600)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFileURL.path)

        // Create a "recent" file in trash
        let recentFileURL = tempRoot.appendingPathComponent(".trash/images/recent-1.png")
        try IntegrationTestSupport.dummyPNGData.write(to: recentFileURL)

        MediaDeleteService.emptyOldTrash(rootURL: tempRoot, olderThan: 30 * 24 * 3600)

        #expect(!fm.fileExists(atPath: oldFileURL.path))
        #expect(fm.fileExists(atPath: recentFileURL.path))
    }

    // MARK: - Trash + Sync Interaction

    @Test("Trashed item is not reimported by SyncService")
    @MainActor func trashThenSyncDoesNotReimport() async throws {
        // Create media + sidecar
        try IntegrationTestSupport.createDummyMedia(id: "trash-sync-1", in: tempRoot)
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "trash-sync-1"), to: tempRoot)

        // Move to trash — removes sidecar from metadata/
        try MediaDeleteService.moveToTrash(filename: "trash-sync-1.png", id: "trash-sync-1", rootURL: tempRoot)

        // Sync should NOT recreate the item (sidecar is gone from metadata/)
        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.isEmpty)
    }
}
