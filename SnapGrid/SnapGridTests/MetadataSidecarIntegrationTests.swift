import Testing
import SwiftData
import Foundation
@testable import SnapGrid

/// Integration tests for MetadataSidecarService file I/O roundtrips.
@Suite(.tags(.integration, .serialization))
struct MetadataSidecarIntegrationTests {
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


    @Test("Write then read sidecar roundtrips all fields")
    @MainActor func writeThenReadSidecarRoundtrips() throws {
        let item = MediaItem(id: "roundtrip-1", mediaType: .image, filename: "roundtrip-1.png", width: 1024, height: 768)
        item.sourceURL = "https://example.com/img.png"
        item.analysisResult = AnalysisResult(
            imageContext: "A settings panel",
            imageSummary: "Settings",
            patterns: [PatternTag(name: "settings", confidence: 0.85)],
            analyzedAt: Date(),
            provider: "openai",
            model: "gpt-4o"
        )

        let primarySpace = Space(id: "sp-rt", name: "UI", order: 0)
        let secondarySpace = Space(id: "sp-secondary", name: "Favorites", order: 1)
        context.insert(primarySpace)
        context.insert(secondarySpace)
        item.addSpace(primarySpace)
        item.addSpace(secondarySpace)
        context.insert(item)
        context.saveOrLog()

        sidecarService.writeSidecar(for: item)
        let read = sidecarService.readSidecar(id: "roundtrip-1")

        let sidecar = try #require(read)
        #expect(sidecar.id == "roundtrip-1")
        #expect(sidecar.type == "image")
        #expect(sidecar.width == 1024)
        #expect(sidecar.height == 768)
        #expect(sidecar.sourceURL == "https://example.com/img.png")
        #expect(sidecar.spaceIds == ["sp-rt", "sp-secondary"])
        #expect(sidecar.normalizedSpaceIDs == ["sp-rt", "sp-secondary"])
        #expect(sidecar.imageContext == "A settings panel")
        #expect(sidecar.imageSummary == "Settings")
        #expect(sidecar.patterns?.count == 1)
        #expect(sidecar.analyzedAt != nil)

        let url = storage.metadataDir.appendingPathComponent("roundtrip-1.json")
        let data = try Data(contentsOf: url)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["spaceIds"] as? [String] == ["sp-rt", "sp-secondary"])
        #expect(json["spaceId"] == nil)
    }

    @Test("Sidecar includes analysis fields when present")
    @MainActor func sidecarIncludesAnalysisFields() throws {
        let item = MediaItem(id: "analysis-fields-1", mediaType: .video, filename: "analysis-fields-1.mp4", width: 1920, height: 1080)
        item.duration = 15.5
        item.analysisResult = AnalysisResult(
            imageContext: "A screen recording of onboarding",
            imageSummary: "Onboarding flow",
            patterns: [
                PatternTag(name: "onboarding", confidence: 0.9),
                PatternTag(name: "animation", confidence: 0.75)
            ],
            analyzedAt: Date(),
            provider: "anthropic",
            model: "claude-3"
        )
        context.insert(item)
        context.saveOrLog()

        sidecarService.writeSidecar(for: item)

        // Read raw JSON to verify structure
        let url = storage.metadataDir.appendingPathComponent("analysis-fields-1.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["imageContext"] as? String == "A screen recording of onboarding")
        #expect(json["imageSummary"] as? String == "Onboarding flow")
        #expect((json["patterns"] as? [[String: Any]])?.count == 2)
        #expect(json["analyzedAt"] != nil)
        #expect(json["type"] as? String == "video")
        #expect(json["duration"] as? Double == 15.5)
    }

    @Test("Write then read spaces.json roundtrips with guidance")
    @MainActor func writeThenReadSpacesRoundtrips() throws {
        defer {
            UserDefaults.standard.removeObject(forKey: "allSpacePrompt")
            UserDefaults.standard.removeObject(forKey: "useAllSpacePrompt")
        }

        let space = Space(id: "sp-spaces-rt", name: "Test Space", order: 0)
        space.customPrompt = "Custom guidance"
        space.useCustomPrompt = true
        context.insert(space)
        context.saveOrLog()

        UserDefaults.standard.set("All space guidance text", forKey: "allSpacePrompt")
        UserDefaults.standard.set(true, forKey: "useAllSpacePrompt")

        sidecarService.writeSpaces(from: context)
        let file = sidecarService.readSpacesFile()

        #expect(file.spaces.count == 1)
        #expect(file.spaces.first?.name == "Test Space")
        #expect(file.spaces.first?.customPrompt == "Custom guidance")
        #expect(file.allSpaceGuidance == "All space guidance text")
        #expect(file.useAllSpaceGuidance == true)
    }

    @Test("Timestamp format is cross-platform compatible (ISO 8601)")
    @MainActor func timestampFormatIsCrossPlatformCompatible() throws {
        let knownDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z

        let item = MediaItem(id: "ts-compat-1", mediaType: .image, filename: "ts-compat-1.png", width: 100, height: 100)
        item.analysisResult = AnalysisResult(
            imageContext: "test", imageSummary: "test", patterns: [],
            analyzedAt: knownDate, provider: "test", model: "test"
        )
        context.insert(item)
        context.saveOrLog()

        sidecarService.writeSidecar(for: item)

        // Read raw JSON and verify ISO 8601 format
        let url = storage.metadataDir.appendingPathComponent("ts-compat-1.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dateStr = try #require(json["analyzedAt"] as? String)

        // Must be parseable by ISO8601DateFormatter (used by both platforms)
        let formatter = ISO8601DateFormatter()
        let parsed = try #require(formatter.date(from: dateStr))

        // Should be within 1 second (ISO 8601 may truncate sub-second)
        #expect(abs(parsed.timeIntervalSince(knownDate)) < 1.0)
    }
}
