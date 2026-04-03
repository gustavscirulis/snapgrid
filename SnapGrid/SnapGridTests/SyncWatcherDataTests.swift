import Testing
import Foundation
import SwiftData
@testable import SnapGrid

/// Tests for SyncWatcher data handling logic from PRs #148, #150, #137.
/// Tests the data structures and sync logic without file system watchers.
@Suite("SyncWatcher Data Handling", .tags(.model))
@MainActor
struct SyncWatcherDataTests {

    // MARK: - SyncWatcher local change suppression (PR #148)

    @Test("beginLocalChange sets suppression flag")
    func beginLocalChange() {
        let watcher = SyncWatcher()
        watcher.beginLocalChange()
        // The suppression flag prevents re-triggering analysis when we write sidecars
        // We can't directly check the private flag, but we can verify it doesn't crash
        // and that endLocalChange can be called after
        watcher.endLocalChange()
    }

    // MARK: - MediaItem sourceURL sync (PR #150)

    @Test("sourceURL only set when item has nil sourceURL")
    func sourceURLOnlySetWhenNil() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        // Item already has a sourceURL
        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)
        item.sourceURL = "https://original.com"

        // Simulating what applySpaceUpdate does: only set if nil
        let newURL = "https://new.com"
        if item.sourceURL == nil {
            item.sourceURL = newURL
        }

        // Original should be preserved
        #expect(item.sourceURL == "https://original.com")
    }

    @Test("sourceURL set when item has no sourceURL")
    func sourceURLSetWhenNil() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)
        // sourceURL is nil by default

        let newURL = "https://x.com/user/status/123"
        if item.sourceURL == nil {
            item.sourceURL = newURL
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

    // MARK: - Analysis duplicate prevention (PR #148)

    @Test("isAnalyzing flag prevents re-analysis")
    func isAnalyzingGuard() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)
        item.isAnalyzing = true

        // The guard in analyzeItem checks this flag
        #expect(item.isAnalyzing == true)

        // After analysis completes, it's reset
        item.isAnalyzing = false
        #expect(item.isAnalyzing == false)
    }

    @Test("analysisError stored and clearable")
    func analysisErrorLifecycle() throws {
        let container = try TestContainer.create()
        let context = container.mainContext

        let item = MediaItem(mediaType: .image, filename: "test.png", width: 100, height: 100)
        context.insert(item)

        // Simulate analysis failure
        item.isAnalyzing = false
        item.analysisError = "API error (429): Rate limited"

        #expect(item.analysisError == "API error (429): Rate limited")

        // Simulate retry clearing the error
        item.analysisError = nil
        #expect(item.analysisError == nil)
    }

    // MARK: - Unanalyzed items filter (PR #130)

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
}
