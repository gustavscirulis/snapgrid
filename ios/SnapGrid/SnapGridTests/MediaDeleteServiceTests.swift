import Testing
import Foundation
@testable import SnapGrid

@Suite("MediaDeleteService", .tags(.filesystem))
struct MediaDeleteServiceTests {

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapGridTest-\(UUID().uuidString)")
        let fm = FileManager.default

        let dirs = ["images", "metadata", "thumbnails", ".trash/images", ".trash/metadata", ".trash/thumbnails"]
        for dir in dirs {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        return root
    }

    private func createDummyFile(at url: URL) throws {
        try Data("test".utf8).write(to: url)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("Moves image, metadata, and thumbnail to trash")
    func moveAllToTrash() throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }
        let fm = FileManager.default

        try createDummyFile(at: root.appendingPathComponent("images/photo.png"))
        try createDummyFile(at: root.appendingPathComponent("metadata/item1.json"))
        try createDummyFile(at: root.appendingPathComponent("thumbnails/item1.jpg"))

        try MediaDeleteService.moveToTrash(filename: "photo.png", id: "item1", rootURL: root)

        #expect(!fm.fileExists(atPath: root.appendingPathComponent("images/photo.png").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("metadata/item1.json").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("thumbnails/item1.jpg").path))

        #expect(fm.fileExists(atPath: root.appendingPathComponent(".trash/images/photo.png").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent(".trash/metadata/item1.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent(".trash/thumbnails/item1.jpg").path))
    }

    @Test("Gracefully handles missing source files")
    func missingSourceFiles() throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }

        // No source files exist — should not throw
        try MediaDeleteService.moveToTrash(filename: "missing.png", id: "missing", rootURL: root)
    }

    @Test("Handles only image file existing")
    func onlyImageExists() throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }
        let fm = FileManager.default

        try createDummyFile(at: root.appendingPathComponent("images/photo.png"))

        try MediaDeleteService.moveToTrash(filename: "photo.png", id: "item1", rootURL: root)

        #expect(fm.fileExists(atPath: root.appendingPathComponent(".trash/images/photo.png").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent(".trash/metadata/item1.json").path))
    }

    @Test("Replaces existing file in trash")
    func replacesExistingInTrash() throws {
        let root = try makeTempRoot()
        defer { cleanup(root) }
        let fm = FileManager.default

        // Pre-existing file in trash
        try Data("old".utf8).write(to: root.appendingPathComponent(".trash/images/photo.png"))
        try createDummyFile(at: root.appendingPathComponent("images/photo.png"))

        try MediaDeleteService.moveToTrash(filename: "photo.png", id: "item1", rootURL: root)

        let data = try Data(contentsOf: root.appendingPathComponent(".trash/images/photo.png"))
        #expect(String(data: data, encoding: .utf8) == "test")
    }
}
