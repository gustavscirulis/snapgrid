import Testing
import Foundation
import SwiftData
@testable import SnapGrid

@Suite("SearchIndexService", .tags(.search))
@MainActor
struct SearchIndexServiceTests {

    // MARK: - Tokenization

    @Test("Tokenize lowercases and splits on non-alphanumeric")
    func tokenizeBasic() {
        let tokens = SearchIndexService.tokenize("Hello World!")
        #expect(tokens == ["hello", "world"])
    }

    @Test("Tokenize filters tokens shorter than 2 characters")
    func tokenizeFiltersShort() {
        let tokens = SearchIndexService.tokenize("I am a big cat")
        #expect(tokens == ["am", "big", "cat"])
    }

    @Test("Tokenize empty string returns empty")
    func tokenizeEmpty() {
        #expect(SearchIndexService.tokenize("").isEmpty)
    }

    @Test("Tokenize handles punctuation and special characters")
    func tokenizePunctuation() {
        let tokens = SearchIndexService.tokenize("UI/UX design — best-practices 2024!")
        #expect(tokens.contains("ui"))
        #expect(tokens.contains("ux"))
        #expect(tokens.contains("design"))
        #expect(tokens.contains("best"))
        #expect(tokens.contains("practices"))
        #expect(tokens.contains("2024"))
    }

    // MARK: - Search with SwiftData

    private func makeItem(id: String, summary: String, context: String, patterns: [String], container: ModelContainer) -> MediaItem {
        let item = MediaItem(id: id, mediaType: .image, filename: "\(id).png", width: 100, height: 100)
        let analysis = AnalysisResult(
            imageContext: context,
            imageSummary: summary,
            patterns: patterns.map { PatternTag(name: $0, confidence: 0.9) },
            provider: "test",
            model: "test"
        )
        let context = container.mainContext
        context.insert(item)
        context.insert(analysis)
        item.analysisResult = analysis
        return item
    }

    @Test("Empty query returns no results")
    func searchEmpty() throws {
        let service = SearchIndexService()
        let results = service.search(query: "")
        #expect(results.isEmpty)
    }

    @Test("Search finds item by pattern name")
    func searchByPattern() throws {
        let container = try TestContainer.create()
        let item = makeItem(id: "1", summary: "Login", context: "A login form", patterns: ["Text Field", "Submit Button"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item])

        let results = service.search(query: "button")
        #expect(results.count == 1)
        #expect(results[0].itemId == "1")
    }

    @Test("Search finds item by summary")
    func searchBySummary() throws {
        let container = try TestContainer.create()
        let item = makeItem(id: "1", summary: "Dashboard", context: "Analytics dashboard", patterns: ["Chart"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item])

        let results = service.search(query: "dashboard")
        #expect(results.count == 1)
    }

    @Test("Multi-term search uses AND logic")
    func searchANDLogic() throws {
        let container = try TestContainer.create()
        let item1 = makeItem(id: "1", summary: "Login", context: "Login form", patterns: ["Button"], container: container)
        let item2 = makeItem(id: "2", summary: "Dashboard", context: "Chart view", patterns: ["Button"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item1, item2])

        // "login button" should only match item1 (has both terms)
        let results = service.search(query: "login button")
        #expect(results.count == 1)
        #expect(results[0].itemId == "1")
    }

    @Test("Prefix matching finds partial terms")
    func searchPrefixMatch() throws {
        let container = try TestContainer.create()
        let item = makeItem(id: "1", summary: "Navigation", context: "Nav bar", patterns: ["Hamburger Menu"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item])

        let results = service.search(query: "nav")
        #expect(!results.isEmpty)
    }

    @Test("Remove from index makes item unsearchable")
    func removeFromIndex() throws {
        let container = try TestContainer.create()
        let item = makeItem(id: "1", summary: "Login", context: "Form", patterns: ["Button"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item])
        #expect(!service.search(query: "login").isEmpty)

        service.removeFromIndex(itemId: "1")
        #expect(service.search(query: "login").isEmpty)
    }

    @Test("Add to index makes new item searchable")
    func addToIndex() throws {
        let container = try TestContainer.create()
        let item1 = makeItem(id: "1", summary: "Login", context: "Form", patterns: ["Button"], container: container)
        let item2 = makeItem(id: "2", summary: "Settings", context: "Config", patterns: ["Toggle"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item1])
        #expect(service.search(query: "toggle").isEmpty)

        service.addToIndex(item: item2)
        #expect(!service.search(query: "toggle").isEmpty)
    }

    @Test("Items without analysis are not indexed")
    func noAnalysisSkipped() throws {
        let container = try TestContainer.create()
        let item = MediaItem(id: "1", mediaType: .image, filename: "test.png", width: 100, height: 100)
        container.mainContext.insert(item)

        let service = SearchIndexService()
        service.buildIndex(items: [item])

        let results = service.search(query: "test")
        #expect(results.isEmpty)
    }

    @Test("Pattern tokens have higher weight than context tokens")
    func fieldWeighting() throws {
        let container = try TestContainer.create()
        // item1: "button" in patterns (weight 3.0)
        let item1 = makeItem(id: "1", summary: "Form", context: "A form", patterns: ["Button"], container: container)
        // item2: "button" in context (weight 1.0)
        let item2 = makeItem(id: "2", summary: "Page", context: "Has a button", patterns: ["Image"], container: container)

        let service = SearchIndexService()
        service.buildIndex(items: [item1, item2])

        let results = service.search(query: "button")
        #expect(results.count == 2)
        #expect(results[0].itemId == "1") // Pattern match should rank higher
    }
}
