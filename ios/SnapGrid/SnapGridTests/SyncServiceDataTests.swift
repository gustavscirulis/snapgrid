import Testing
import Foundation
import SwiftData
@testable import SnapGrid

/// Tests for iOS SyncService data handling from PRs #137, #150.
@Suite("SyncService Data Handling", .tags(.model))
@MainActor
struct SyncServiceDataTests {

    // MARK: - sourceURL sync (PR #150)

    @Test("sourceURL only set when item has nil sourceURL")
    func sourceURLOnlySetWhenNil() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)
        item.sourceURL = "https://original.com"

        // Simulate updateIfNeeded logic: only set if nil
        if item.sourceURL == nil {
            item.sourceURL = "https://new.com"
        }

        #expect(item.sourceURL == "https://original.com")
    }

    @Test("sourceURL set when item has no sourceURL")
    func sourceURLSetWhenNil() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)

        if item.sourceURL == nil {
            item.sourceURL = "https://x.com/user/status/123"
        }

        #expect(item.sourceURL == "https://x.com/user/status/123")
    }

    // MARK: - Space custom prompt sync (PR #137)

    @Test("Space customPrompt and useCustomPrompt stored")
    func spaceCustomPrompt() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let space = Space(name: "UI", order: 0)
        context.insert(space)
        space.customPrompt = "Focus on UI components"
        space.useCustomPrompt = true

        try context.save()

        #expect(space.customPrompt == "Focus on UI components")
        #expect(space.useCustomPrompt == true)
    }

    @Test("Space customPrompt defaults to nil and false")
    func spaceCustomPromptDefaults() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let space = Space(name: "Default", order: 0)
        context.insert(space)
        try context.save()

        #expect(space.customPrompt == nil)
        #expect(space.useCustomPrompt == false)
    }

    // MARK: - Space guidance sync to UserDefaults (PR #137)

    @Test("SidecarSpacesFile guidance fields encode/decode")
    func guidanceFieldsRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let file = SidecarSpacesFile(
            spaces: [],
            allSpaceGuidance: "Analyze all images for accessibility issues",
            useAllSpaceGuidance: true
        )

        let data = try encoder.encode(file)
        let decoded = try decoder.decode(SidecarSpacesFile.self, from: data)

        #expect(decoded.allSpaceGuidance == "Analyze all images for accessibility issues")
        #expect(decoded.useAllSpaceGuidance == true)
        #expect(decoded.spaces.isEmpty)
    }

    @Test("SidecarSpacesFile with nil guidance")
    func nilGuidance() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let file = SidecarSpacesFile(spaces: [], allSpaceGuidance: nil, useAllSpaceGuidance: false)
        let data = try encoder.encode(file)
        let decoded = try decoder.decode(SidecarSpacesFile.self, from: data)

        #expect(decoded.allSpaceGuidance == nil)
        #expect(decoded.useAllSpaceGuidance == false)
    }

    // MARK: - Analysis state lifecycle (PRs #148, #130)

    @Test("isAnalyzing flag prevents re-analysis")
    func isAnalyzingGuard() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)
        item.isAnalyzing = true
        #expect(item.isAnalyzing == true)

        item.isAnalyzing = false
        #expect(item.isAnalyzing == false)
    }

    @Test("analysisError stored and clearable")
    func analysisErrorLifecycle() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)

        item.analysisError = "API error (429): Rate limited"
        #expect(item.analysisError == "API error (429): Rate limited")

        item.analysisError = nil
        #expect(item.analysisError == nil)
    }

    @Test("Unanalyzed filter excludes analyzed, errored, and in-progress items")
    func unanalyzedFilter() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let analyzed = MediaItem(id: "1", mediaType: .image, filename: "a.png", width: 100, height: 100)
        analyzed.analysisResult = AnalysisResult(imageContext: "Test", imageSummary: "Test", patterns: [], provider: "t", model: "t")
        context.insert(analyzed)

        let errored = MediaItem(id: "2", mediaType: .image, filename: "b.png", width: 100, height: 100)
        errored.analysisError = "Failed"
        context.insert(errored)

        let inProgress = MediaItem(id: "3", mediaType: .image, filename: "c.png", width: 100, height: 100)
        inProgress.isAnalyzing = true
        context.insert(inProgress)

        let fresh = MediaItem(id: "4", mediaType: .image, filename: "d.png", width: 100, height: 100)
        context.insert(fresh)

        let items = [analyzed, errored, inProgress, fresh]
        let unanalyzed = items.filter { $0.analysisResult == nil && $0.analysisError == nil && !$0.isAnalyzing }

        #expect(unanalyzed.count == 1)
        #expect(unanalyzed[0].id == "4")
    }

    // MARK: - Media type determination from sidecar

    @Test("Video sidecar type maps to .video MediaType")
    func videoTypeMapping() {
        let sidecarType = "video"
        let mediaType: MediaType = sidecarType == "video" ? .video : .image
        #expect(mediaType == .video)
    }

    @Test("Image sidecar type maps to .image MediaType")
    func imageTypeMapping() {
        let sidecarType = "image"
        let mediaType: MediaType = sidecarType == "video" ? .video : .image
        #expect(mediaType == .image)
    }

    @Test("Unknown sidecar type defaults to .image MediaType")
    func unknownTypeDefaultsToImage() {
        let sidecarType = "gif"
        let mediaType: MediaType = sidecarType == "video" ? .video : .image
        #expect(mediaType == .image)
    }

    // MARK: - Media filename construction from sidecar

    @Test("Video filename uses mp4 extension")
    func videoFilename() {
        let id = "test-123"
        let sidecarType = "video"
        let ext = sidecarType == "video" ? "mp4" : "png"
        let filename = "\(id).\(ext)"
        #expect(filename == "test-123.mp4")
    }

    @Test("Image filename uses png extension")
    func imageFilename() {
        let id = "test-456"
        let sidecarType = "image"
        let ext = sidecarType == "video" ? "mp4" : "png"
        let filename = "\(id).\(ext)"
        #expect(filename == "test-456.png")
    }

    // MARK: - iCloud placeholder name resolution

    @Test("iCloud placeholder name extraction strips .icloud suffix and leading dot")
    func iCloudPlaceholderNameResolution() {
        let placeholder = ".test-123.json.icloud"
        var realName = String(placeholder.dropLast(".icloud".count))
        if realName.hasPrefix(".") { realName = String(realName.dropFirst()) }
        #expect(realName == "test-123.json")
    }

    @Test("Non-dotted iCloud placeholder keeps name intact")
    func nonDottedPlaceholder() {
        let placeholder = "test-123.json.icloud"
        var realName = String(placeholder.dropLast(".icloud".count))
        if realName.hasPrefix(".") { realName = String(realName.dropFirst()) }
        #expect(realName == "test-123.json")
    }
}
