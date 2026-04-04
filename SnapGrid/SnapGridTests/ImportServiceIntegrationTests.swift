import Testing
import SwiftData
import AppKit
@testable import SnapGrid

/// Integration tests for Mac ImportService: file → SwiftData → sidecar flow.
/// Analysis is skipped because no API key is configured in the test environment.
@Suite(.tags(.integration))
struct ImportServiceIntegrationTests {
    let tempRoot: URL
    let storage: MediaStorageService
    let sidecarService: MetadataSidecarService
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        tempRoot = try IntegrationTestSupport.makeTempRoot()
        storage = MediaStorageService(baseURL: tempRoot)
        sidecarService = MetadataSidecarService(storage: storage)
        container = try TestContainer.create()
        context = ModelContext(container)
    }


    /// Create a minimal 2x2 PNG file for import testing.
    private func createTestPNG() throws -> URL {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw TestError.cannotCreatePNG
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        try pngData.write(to: tempFile)
        return tempFile
    }

    enum TestError: Error { case cannotCreatePNG }

    @Test("Import creates MediaItem in SwiftData")
    @MainActor func importFileCreatesMediaItem() async throws {
        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: nil)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.mediaType == .image)
        #expect(item.width > 0)
        #expect(item.height > 0)
    }

    @Test("Import copies media file to storage directory")
    @MainActor func importFileCopiesMediaToStorage() async throws {
        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: nil)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)

        #expect(storage.mediaExists(filename: item.filename))
    }

    @Test("Import writes sidecar JSON to metadata directory")
    @MainActor func importFileWritesSidecar() async throws {
        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: nil)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)

        let sidecar = sidecarService.readSidecar(id: item.id)
        #expect(sidecar != nil)
        #expect(sidecar?.type == "image")
        #expect(sidecar?.width == item.width)
    }

    @Test("Import assigns space when spaceId provided")
    @MainActor func importFileAssignsSpace() async throws {
        let space = Space(id: "sp-import", name: "Imports", order: 0)
        context.insert(space)
        context.saveOrLog()

        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: "sp-import")

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)
        #expect(item.space?.id == "sp-import")
    }

    @Test("Import sets sourceURL after insert")
    @MainActor func importFileSetsSourceURL() async throws {
        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: nil, sourceURL: "https://x.com/post/789")

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)
        #expect(item.sourceURL == "https://x.com/post/789")
    }

    @Test("Sidecar references an item that exists in SwiftData (save before sidecar)")
    @MainActor func importFileSavesBeforeSidecar() async throws {
        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: nil)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        let item = try #require(items.first)

        // The sidecar's ID must match an item that was saved to the DB
        let sidecar = try #require(sidecarService.readSidecar(id: item.id))
        #expect(sidecar.id == item.id)
    }

    @Test("Import then sync does not duplicate the item")
    @MainActor func importThenSyncDoesNotDuplicate() async throws {
        let pngURL = try createTestPNG()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        try await importService.importSingleFile(pngURL, into: context, spaceId: nil)

        // Now run SyncWatcher initial sync on the same directory
        let watcher = SyncWatcher(storage: storage, sidecarService: sidecarService)
        await watcher.initialSync(context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.count == 1) // Should NOT have duplicated
    }

    @Test("Import rejects unsupported file extension")
    @MainActor func importRejectsUnsupportedExtension() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let importService = ImportService(storage: storage, sidecarService: sidecarService)
        await #expect(throws: ImportService.ImportError.self) {
            try await importService.importSingleFile(tempFile, into: context, spaceId: nil)
        }
    }
}
