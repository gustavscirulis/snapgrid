import Foundation
import SwiftData

struct PatternTag: Codable, Hashable, Sendable {
    let name: String
    let confidence: Double
}

@Model
class AnalysisResult {
    var imageContext: String
    var imageSummary: String
    var patterns: [PatternTag]
    var analyzedAt: Date
    var provider: String
    var model: String

    init(imageContext: String, imageSummary: String, patterns: [PatternTag], analyzedAt: Date = .now, provider: String, model: String) {
        self.imageContext = imageContext
        self.imageSummary = imageSummary
        self.patterns = patterns
        self.analyzedAt = analyzedAt
        self.provider = provider
        self.model = model
    }
}
