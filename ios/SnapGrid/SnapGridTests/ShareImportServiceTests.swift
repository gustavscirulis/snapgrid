import Testing
import Foundation
@testable import SnapGrid

@Suite("ShareImportService", .tags(.filesystem))
struct ShareImportServiceTests {

    // MARK: - mediaExtension

    @Test("Image sidecar returns png extension")
    func imageExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-image.json")
        let json = Data("""
        {"id": "test", "type": "image", "width": 100, "height": 100, "createdAt": "2024-01-01T00:00:00Z"}
        """.utf8)
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == "png")
    }

    @Test("Video sidecar returns mp4 extension")
    func videoExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-video.json")
        let json = Data("""
        {"id": "test", "type": "video", "width": 1280, "height": 720, "createdAt": "2024-01-01T00:00:00Z"}
        """.utf8)
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == "mp4")
    }

    @Test("Invalid JSON returns nil")
    func invalidJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-bad.json")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == nil)
    }

    @Test("Missing type field returns nil")
    func missingType() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-notype.json")
        let json = Data("""
        {"id": "test", "width": 100, "height": 100}
        """.utf8)
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == nil)
    }

    @Test("Nonexistent file returns nil")
    func nonexistentFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID()).json")
        #expect(ShareImportService.mediaExtension(for: url) == nil)
    }
}
