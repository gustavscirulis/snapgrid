import Foundation
import CoreGraphics

struct SnapGridItem: Identifiable, Codable, Hashable {
    let id: String
    let type: String
    let width: Int
    let height: Int
    let createdAt: String
    var title: String?
    var description: String?
    var patterns: [PatternTag]?
    var imageContext: String?
    var spaceId: String?
    var duration: Double?

    var isVideo: Bool { type == "video" }

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1.0 }
        return CGFloat(width) / CGFloat(height)
    }

    /// Aspect ratio capped at 1:2 for grid display. Tall screenshots
    /// (height > width * 2) are capped to prevent dominating the grid.
    var gridAspectRatio: CGFloat {
        max(aspectRatio, 0.5)
    }

    var createdDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
    }

    // Local file URLs — set after loading, not from JSON
    var thumbnailURL: URL?
    var mediaURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, type, width, height, createdAt, title, description
        case patterns, imageContext, spaceId, duration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SnapGridItem, rhs: SnapGridItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct PatternTag: Codable, Hashable {
    let name: String
    let confidence: Double
    var imageContext: String?
    var imageSummary: String?
}
