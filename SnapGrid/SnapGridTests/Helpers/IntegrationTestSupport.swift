import Foundation
@testable import SnapGrid

/// Shared helpers for Mac integration tests that use temp directories.
/// Each test suite gets a unique `/tmp/SnapGridTests/{UUID}/` root
/// so parallel test runs (including across git worktrees) never collide.
enum IntegrationTestSupport {

    // MARK: - Temp Directory

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

    static func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Sidecar Helpers

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static func writeSidecarJSON(_ sidecar: SidecarMetadata, to rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("metadata/\(sidecar.id).json")
        let data = try encoder.encode(sidecar)
        try data.write(to: url, options: .atomic)
    }

    static func writeSpacesJSON(_ file: SidecarSpacesFile, to rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("spaces.json")
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    static func writeLegacySpacesJSON(_ spaces: [SidecarSpace], to rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("spaces.json")
        let data = try encoder.encode(spaces)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Dummy Media

    static let dummyPNGData: Data = {
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
            0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE, 0x42, 0x60, 0x82
        ]
        return Data(bytes)
    }()

    static func createDummyMedia(id: String, ext: String = "png", in rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("images/\(id).\(ext)")
        try dummyPNGData.write(to: url, options: .atomic)
    }

    static func createDummyThumbnail(id: String, in rootURL: URL) throws {
        let url = rootURL.appendingPathComponent("thumbnails/\(id).jpg")
        try dummyPNGData.write(to: url, options: .atomic)
    }

    // MARK: - Sidecar Factory

    static func makeSidecar(
        id: String,
        type: String = "image",
        width: Int = 800,
        height: Int = 600,
        spaceIds: [String]? = nil,
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
            spaceIds: spaceIds,
            spaceId: spaceId,
            imageContext: imageContext,
            imageSummary: imageSummary,
            patterns: patterns,
            sourceURL: sourceURL,
            analyzedAt: analyzedAt
        )
    }
}
