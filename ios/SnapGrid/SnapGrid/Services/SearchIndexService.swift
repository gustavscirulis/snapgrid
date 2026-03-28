import Foundation

struct SearchResult {
    let itemId: String
    let score: Double
}

/// Full-text search using an inverted index with BM25 scoring.
/// Builds the index at startup from metadata; queries are <1ms.
@Observable
@MainActor
final class SearchIndexService {

    // MARK: - BM25 Parameters

    private let k1 = 1.2
    private let b = 0.75

    // MARK: - Index Structures

    private var postings: [String: [(itemId: String, tf: Double)]] = [:]
    private var docLengths: [String: Double] = [:]
    private var avgDocLength: Double = 0
    private var docCount: Int = 0
    private var sortedVocabulary: [String] = []

    // MARK: - Field Weights

    private let patternWeight = 3.0
    private let summaryWeight = 2.0
    private let contextWeight = 1.0

    // MARK: - Tokenization

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    // MARK: - Index Building

    func buildIndex(items: [MediaItem]) {
        postings = [:]
        docLengths = [:]

        for item in items {
            indexItem(item)
        }

        finalizeIndex()
        print("[SearchIndex] Built index: \(docCount) docs, \(postings.count) unique tokens")
    }

    func addToIndex(item: MediaItem) {
        removeFromIndex(itemId: item.id)
        indexItem(item)
        finalizeIndex()
    }

    func removeFromIndex(itemId: String) {
        guard docLengths.removeValue(forKey: itemId) != nil else { return }

        for token in postings.keys {
            postings[token]?.removeAll { $0.itemId == itemId }
            if postings[token]?.isEmpty == true {
                postings[token] = nil
            }
        }

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

        var scores: [String: Double] = [:]
        var termMatches: [String: Int] = [:]

        for term in queryTerms {
            var matchedIds = Set<String>()

            if let list = postings[term] {
                let idf = idfScore(documentFrequency: list.count)
                for entry in list {
                    scores[entry.itemId, default: 0] += bm25Term(tf: entry.tf, docLength: docLengths[entry.itemId] ?? 0, idf: idf)
                    matchedIds.insert(entry.itemId)
                }
            }

            let prefixMatches = tokensWithPrefix(term)
            for matchedToken in prefixMatches {
                guard matchedToken != term, let list = postings[matchedToken] else { continue }
                let idf = idfScore(documentFrequency: list.count)
                for entry in list {
                    scores[entry.itemId, default: 0] += bm25Term(tf: entry.tf, docLength: docLengths[entry.itemId] ?? 0, idf: idf) * 0.7
                    matchedIds.insert(entry.itemId)
                }
            }

            for id in matchedIds {
                termMatches[id, default: 0] += 1
            }
        }

        let requiredTermCount = queryTerms.count
        return scores
            .filter { termMatches[$0.key] == requiredTermCount }
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
}
