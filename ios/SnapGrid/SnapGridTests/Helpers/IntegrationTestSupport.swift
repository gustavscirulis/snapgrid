import Foundation
@testable import SnapGrid

/// Shared helpers for integration tests that use temp directories.
/// Each test suite gets a unique `/tmp/SnapGridTests/{UUID}/` root
/// so parallel test runs (including across git worktrees) never collide.
enum IntegrationTestSupport {

    // MARK: - Temp Directory

    /// Creates a unique temp root with the full SnapGrid directory structure.
    static func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapGridTests")
            .appendingPathComponent(UUID().uuidString)
        for sub in ["images", "metadata", "thumbnails",
                     ".trash/images", ".trash/metadata", ".trash/thumbnails"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub),
                withIntermediateDirectories: true)
        }
        return root
    }

    /// Removes the entire temp root. Call in deinit.
    static func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Sidecar Helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Write a SidecarMetadata JSON file to the temp metadata directory.
    static func writeSidecarJSON(_ sidecar: SidecarMetadata, to rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("metadata/\(sidecar.id).json")
        let data = try encoder.encode(sidecar)
        try data.write(to: url, options: .atomic)
    }

    /// Write a spaces.json file (wrapper format with guidance).
    static func writeSpacesJSON(_ file: SidecarSpacesFile, to rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("spaces.json")
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    /// Write a legacy bare-array spaces.json.
    static func writeLegacySpacesJSON(_ spaces: [SidecarSpace], to rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("spaces.json")
        let data = try encoder.encode(spaces)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Dummy Media

    /// Minimal valid PNG bytes (1x1 pixel, red).
    static let dummyPNGData: Data = {
        // 1x1 red PNG — 67 bytes
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
            0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
            0x44, 0xAE, 0x42, 0x60, 0x82
        ]
        return Data(bytes)
    }()

    /// Create a dummy media file in the temp images directory.
    static func createDummyMedia(id: String, ext: String = "png", in rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("images/\(id).\(ext)")
        try dummyPNGData.write(to: url, options: .atomic)
    }

    /// Create a dummy thumbnail in the temp thumbnails directory.
    static func createDummyThumbnail(id: String, in rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("thumbnails/\(id).jpg")
        try dummyPNGData.write(to: url, options: .atomic)
    }

    // MARK: - Sidecar Factory

    /// Create a basic SidecarMetadata for testing.
    static func makeSidecar(
        id: String,
        type: String = "image",
        width: Int = 800,
        height: Int = 600,
        spaceId: String? = nil,
        imageContext: String? = nil,
        imageSummary: String? = nil,
        patterns: [SidecarPattern]? = nil,
        sourceURL: String? = nil,
        analyzedAt: Date? = nil,
        duration: Double? = nil
    ) -> SidecarMetadata {
        SidecarMetadata(
            id: id,
            type: type,
            width: width,
            height: height,
            createdAt: Date(),
            duration: duration,
            spaceId: spaceId,
            imageContext: imageContext,
            imageSummary: imageSummary,
            patterns: patterns,
            sourceURL: sourceURL,
            analyzedAt: analyzedAt
        )
    }
}
