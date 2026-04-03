import Testing
import Foundation
@testable import SnapGrid

@Suite("Sidecar Serialization", .tags(.serialization))
struct SidecarCodableTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - SidecarMetadata

    @Test("SidecarMetadata encode/decode roundtrip")
    func metadataRoundtrip() throws {
        let original = SidecarMetadata(
            id: "abc-123",
            type: "image",
            width: 1920,
            height: 1080,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            duration: nil,
            spaceId: "space-1",
            imageContext: "A landscape photo",
            imageSummary: "Landscape",
            patterns: [
                SidecarPattern(name: "Mountain", confidence: 0.95),
                SidecarPattern(name: "Sky", confidence: 0.88)
            ],
            sourceURL: "https://x.com/user/status/123"
        )

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(SidecarMetadata.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.width == original.width)
        #expect(decoded.height == original.height)
        #expect(decoded.spaceId == original.spaceId)
        #expect(decoded.imageContext == original.imageContext)
        #expect(decoded.imageSummary == original.imageSummary)
        #expect(decoded.patterns?.count == 2)
        #expect(decoded.patterns?[0].name == "Mountain")
        #expect(decoded.sourceURL == "https://x.com/user/status/123")
    }

    @Test("SidecarMetadata nil optionals preserved")
    func metadataNilOptionals() throws {
        let original = SidecarMetadata(
            id: "test-id",
            type: "video",
            width: 640,
            height: 480,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            duration: 12.5,
            spaceId: nil,
            imageContext: nil,
            imageSummary: nil,
            patterns: nil,
            sourceURL: nil
        )

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(SidecarMetadata.self, from: data)

        #expect(decoded.spaceId == nil)
        #expect(decoded.imageContext == nil)
        #expect(decoded.imageSummary == nil)
        #expect(decoded.patterns == nil)
        #expect(decoded.duration == 12.5)
        #expect(decoded.sourceURL == nil)
    }

    // MARK: - sourceURL (PR #150)

    @Test("SidecarMetadata with sourceURL roundtrip")
    func sourceURLRoundtrip() throws {
        let original = SidecarMetadata(
            id: "twitter-import",
            type: "video",
            width: 1280,
            height: 720,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            duration: 30.0,
            spaceId: nil,
            imageContext: nil,
            imageSummary: nil,
            patterns: nil,
            sourceURL: "https://x.com/user/status/1234567890"
        )

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(SidecarMetadata.self, from: data)

        #expect(decoded.sourceURL == "https://x.com/user/status/1234567890")
    }

    @Test("SidecarMetadata without sourceURL decodes as nil")
    func sourceURLMissing() throws {
        let json = """
        {
            "id": "old-item",
            "type": "image",
            "width": 100,
            "height": 100,
            "createdAt": "2023-11-14T22:13:20Z"
        }
        """
        let data = Data(json.utf8)
        let decoded = try Self.decoder.decode(SidecarMetadata.self, from: data)
        #expect(decoded.sourceURL == nil)
    }

    // MARK: - SidecarSpacesFile

    @Test("SidecarSpacesFile wrapper format roundtrip")
    func spacesFileWrapperRoundtrip() throws {
        let original = SidecarSpacesFile(
            spaces: [
                SidecarSpace(id: "s1", name: "UI", order: 0, createdAt: Date(timeIntervalSince1970: 1700000000), customPrompt: "Focus on UI", useCustomPrompt: true),
                SidecarSpace(id: "s2", name: "Photos", order: 1, createdAt: Date(timeIntervalSince1970: 1700000000), customPrompt: nil, useCustomPrompt: false)
            ],
            allSpaceGuidance: "General guidance text",
            useAllSpaceGuidance: true
        )

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(SidecarSpacesFile.self, from: data)

        #expect(decoded.spaces.count == 2)
        #expect(decoded.spaces[0].name == "UI")
        #expect(decoded.spaces[0].customPrompt == "Focus on UI")
        #expect(decoded.spaces[0].useCustomPrompt == true)
        #expect(decoded.spaces[1].customPrompt == nil)
        #expect(decoded.allSpaceGuidance == "General guidance text")
        #expect(decoded.useAllSpaceGuidance == true)
    }

    @Test("Legacy bare array decodes as SidecarSpacesFile spaces")
    func legacyBareArrayDecodes() throws {
        let spaces = [
            SidecarSpace(id: "s1", name: "Legacy", order: 0, createdAt: Date(timeIntervalSince1970: 1700000000), customPrompt: nil, useCustomPrompt: false)
        ]
        let data = try Self.encoder.encode(spaces)

        let wrapperResult = try? Self.decoder.decode(SidecarSpacesFile.self, from: data)
        #expect(wrapperResult == nil)

        let arrayResult = try Self.decoder.decode([SidecarSpace].self, from: data)
        #expect(arrayResult.count == 1)
        #expect(arrayResult[0].name == "Legacy")
    }

    @Test("ISO 8601 dates survive encode/decode")
    func iso8601DatesPreserved() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let space = SidecarSpace(
            id: "test",
            name: "Test",
            order: 0,
            createdAt: date,
            customPrompt: nil,
            useCustomPrompt: false
        )

        let data = try Self.encoder.encode(space)
        let decoded = try Self.decoder.decode(SidecarSpace.self, from: data)

        #expect(abs(decoded.createdAt.timeIntervalSince(date)) < 1.0)
    }
}
