import Accelerate
import Foundation
import NaturalLanguage

struct SearchResult {
    let itemId: String
    let score: Double
}

/// Full-text search using an inverted index with BM25 scoring, plus lightweight
/// word-vector embeddings for synonym matching. Queries are <1ms.
@Observable
@MainActor
final class SearchIndexService {

    // MARK: - BM25 Parameters

    private let k1 = 1.2
    private let b = 0.75

    // MARK: - Index Structures

    /// Token → list of (itemId, weighted term frequency)
    private var postings: [String: [(itemId: String, tf: Double)]] = [:]
    /// Item ID → total weighted token count
    private var docLengths: [String: Double] = [:]
    /// Average document length across all indexed items
    private var avgDocLength: Double = 0
    /// Total number of indexed documents
    private var docCount: Int = 0
    /// Sorted vocabulary for prefix search via binary search
    private var sortedVocabulary: [String] = []

    // MARK: - Embedding Structures

    /// Pre-computed item embeddings (averaged word vectors). Built in background.
    private var itemEmbeddings: [String: [Double]] = [:]
    /// Whether embeddings are ready for search
    private var embeddingsReady = false
    /// Word embedding model (static word vectors, no neural network)
    nonisolated(unsafe) private static let wordEmbedding = NLEmbedding.wordEmbedding(for: .english)
    /// Embedding dimension
    private var embeddingDimension: Int { Self.wordEmbedding?.dimension ?? 0 }
    /// Minimum similarity for embedding-only results
    private let embeddingSimilarityThreshold: Double = 0.65
    /// Only use embeddings when BM25 returns fewer than this many results
    private let embeddingFallbackThreshold = 3

    // MARK: - Field Weights

    private let patternWeight = 3.0
    private let summaryWeight = 2.0
    private let contextWeight = 1.0

    // MARK: - Tokenization & Text Helpers

    private nonisolated static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// Compose searchable text from analysis result fields.
    private nonisolated static func searchableText(from result: AnalysisResult) -> String {
        "\(result.imageSummary) \(result.patterns.map(\.name).joined(separator: " ")) \(result.imageContext)"
    }

    // MARK: - Index Building

    /// Build the full index from all items. Call once at startup.
    func buildIndex(items: [MediaItem]) {
        postings = [:]
        docLengths = [:]

        for item in items {
            indexItem(item)
        }

        finalizeIndex()
        print("[SearchIndex] Built index: \(docCount) docs, \(postings.count) unique tokens")
    }

    /// Build embeddings for all items in the background. Non-blocking.
    func buildEmbeddingsInBackground(items: [MediaItem]) {
        guard Self.wordEmbedding != nil else {
            print("[SearchIndex] Word embeddings not available, skipping")
            return
        }

        // Extract text data on main actor (SwiftData models are @MainActor)
        var textData: [(id: String, text: String)] = []
        for item in items {
            guard let result = item.analysisResult else { continue }
            let text = Self.searchableText(from: result)
            textData.append((id: item.id, text: text))
        }

        // Compute embeddings off main actor
        Task.detached {
            var embeddings: [String: [Double]] = [:]
            for entry in textData {
                if let vec = Self.averageWordVectors(entry.text) {
                    embeddings[entry.id] = vec
                }
            }

            await MainActor.run {
                self.itemEmbeddings = embeddings
                self.embeddingsReady = true
                print("[SearchIndex] Built \(embeddings.count) word-vector embeddings in background")
            }
        }
    }

    /// Add a single item to the index (after analysis completes).
    func addToIndex(item: MediaItem) {
        removeFromIndex(itemId: item.id)
        indexItem(item)
        finalizeIndex()

        // Also compute embedding
        if let result = item.analysisResult {
            let text = Self.searchableText(from: result)
            if let vec = Self.averageWordVectors(text) {
                itemEmbeddings[item.id] = vec
            }
        }
    }

    /// Remove a single item from the index.
    func removeFromIndex(itemId: String) {
        guard docLengths.removeValue(forKey: itemId) != nil else { return }

        for token in postings.keys {
            postings[token]?.removeAll { $0.itemId == itemId }
            if postings[token]?.isEmpty == true {
                postings[token] = nil
            }
        }

        itemEmbeddings.removeValue(forKey: itemId)
        finalizeIndex()
    }

    private func indexItem(_ item: MediaItem) {
        guard let result = item.analysisResult else { return }

        let patternTokens = result.patterns.flatMap { Self.tokenize($0.name) }
        let summaryTokens = Self.tokenize(result.imageSummary)
        let contextTokens = Self.tokenize(result.imageContext)

        var termFreqs: [String: Double] = [:]
        for token in patternTokens { termFreqs[token, default: 0] += patternWeight }
        for token in summaryTokens { termFreqs[token, default: 0] += summaryWeight }
        for token in contextTokens { termFreqs[token, default: 0] += contextWeight }

        guard !termFreqs.isEmpty else { return }

        let docLength = termFreqs.values.reduce(0, +)
        docLengths[item.id] = docLength

        for (token, tf) in termFreqs {
            postings[token, default: []].append((itemId: item.id, tf: tf))
        }
    }

    private func finalizeIndex() {
        docCount = docLengths.count
        let totalLength = docLengths.values.reduce(0, +)
        avgDocLength = docCount > 0 ? totalLength / Double(docCount) : 0
        sortedVocabulary = postings.keys.sorted()
    }

    // MARK: - Search

    func search(query: String) -> [SearchResult] {
        let queryTerms = Self.tokenize(query)
        guard !queryTerms.isEmpty else { return [] }

        // Stage 1: BM25 keyword search with AND logic
        var bm25Scores: [String: Double] = [:]
        var termMatches: [String: Int] = [:]

        for term in queryTerms {
            var matchedIds = Set<String>()

            if let list = postings[term] {
                let idf = idfScore(documentFrequency: list.count)
                for entry in list {
                    bm25Scores[entry.itemId, default: 0] += bm25Term(tf: entry.tf, docLength: docLengths[entry.itemId] ?? 0, idf: idf)
                    matchedIds.insert(entry.itemId)
                }
            }

            let prefixMatches = tokensWithPrefix(term)
            for matchedToken in prefixMatches {
                guard matchedToken != term, let list = postings[matchedToken] else { continue }
                let idf = idfScore(documentFrequency: list.count)
                for entry in list {
                    bm25Scores[entry.itemId, default: 0] += bm25Term(tf: entry.tf, docLength: docLengths[entry.itemId] ?? 0, idf: idf) * 0.7
                    matchedIds.insert(entry.itemId)
                }
            }

            for id in matchedIds {
                termMatches[id, default: 0] += 1
            }
        }

        let requiredTermCount = queryTerms.count
        var results: [String: Double] = [:]
        for (id, score) in bm25Scores where termMatches[id] == requiredTermCount {
            results[id] = score
        }

        // Stage 2: Embedding similarity — only when BM25 found few/no keyword matches
        if embeddingsReady, results.count < embeddingFallbackThreshold,
           let queryVec = Self.averageWordVectors(query) {
            let dim = queryVec.count
            for (itemId, itemVec) in itemEmbeddings {
                // Skip items already found by BM25
                if results[itemId] != nil { continue }
                guard itemVec.count == dim else { continue }

                var dot = 0.0
                vDSP_dotprD(queryVec, 1, itemVec, 1, &dot, vDSP_Length(dim))
                if dot >= embeddingSimilarityThreshold {
                    // Add with a lower score so BM25 matches always rank first
                    results[itemId] = dot * 0.5
                }
            }
        }

        return results
            .map { SearchResult(itemId: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }
    }

    // MARK: - BM25 Scoring

    private func idfScore(documentFrequency df: Int) -> Double {
        guard docCount > 0, df > 0 else { return 0 }
        return log((Double(docCount) - Double(df) + 0.5) / (Double(df) + 0.5) + 1.0)
    }

    private func bm25Term(tf: Double, docLength: Double, idf: Double) -> Double {
        let numerator = tf * (k1 + 1)
        let denominator = tf + k1 * (1 - b + b * docLength / max(avgDocLength, 1))
        return idf * numerator / denominator
    }

    // MARK: - Prefix Matching

    private func tokensWithPrefix(_ prefix: String) -> [String] {
        guard !sortedVocabulary.isEmpty, prefix.count >= 2 else { return [] }

        var lo = 0, hi = sortedVocabulary.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedVocabulary[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        var matches: [String] = []
        while lo < sortedVocabulary.count && sortedVocabulary[lo].hasPrefix(prefix) {
            matches.append(sortedVocabulary[lo])
            lo += 1
        }
        return matches
    }

    // MARK: - Word Vector Embeddings

    /// Average word vectors for a text string. Uses static word embeddings (no neural network).
    /// Returns an L2-normalized vector, or nil if no words have embeddings.
    private nonisolated static func averageWordVectors(_ text: String) -> [Double]? {
        guard let embedding = wordEmbedding else { return nil }
        let dim = embedding.dimension

        let words = tokenize(text)

        var sum = [Double](repeating: 0, count: dim)
        var count = 0

        for word in words {
            guard let vec = embedding.vector(for: word) else { continue }
            vDSP.add(sum, vec, result: &sum)
            count += 1
        }

        guard count > 0 else { return nil }

        // Average
        var divisor = Double(count)
        vDSP_vsdivD(sum, 1, &divisor, &sum, 1, vDSP_Length(dim))

        // L2 normalize
        var mag = 0.0
        vDSP_dotprD(sum, 1, sum, 1, &mag, vDSP_Length(dim))
        mag = sqrt(mag)
        guard mag > 0 else { return nil }
        vDSP_vsdivD(sum, 1, &mag, &sum, 1, vDSP_Length(dim))

        return sum
    }
}
