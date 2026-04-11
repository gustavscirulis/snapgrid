import Foundation
import SwiftData
import CoreGraphics

enum MediaType: String, Codable, Sendable {
    case image, video
}

@Model
class MediaItem {
    @Attribute(.unique) var id: String
    var mediaType: MediaType
    var filename: String
    var width: Int
    var height: Int
    var createdAt: Date
    var spaces: [Space] = []

    // AI analysis
    @Relationship(deleteRule: .cascade) var analysisResult: AnalysisResult?
    var isAnalyzing: Bool = false
    var analysisError: String?

    // Video
    var duration: Double?

    // Import tracking
    var sourceId: String?
    var sourceURL: String?

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1.0 }
        return CGFloat(width) / CGFloat(height)
    }

    /// Aspect ratio capped at 1:2 for grid display. Prevents tall screenshots from dominating.
    var gridAspectRatio: CGFloat {
        max(aspectRatio, 0.5)
    }

    var isVideo: Bool { mediaType == .video }

    /// Resolve media file URL from FileSystemManager directories.
    @MainActor
    var mediaURL: URL? {
        FileSystemManager.shared?.imagesDir?.appendingPathComponent(filename)
    }

    /// Resolve thumbnail URL from FileSystemManager directories.
    @MainActor
    var thumbnailURL: URL? {
        guard !isVideo else { return nil }
        return FileSystemManager.shared?.thumbnailsDir?.appendingPathComponent("\(id).jpg")
    }

    init(id: String = UUID().uuidString, mediaType: MediaType, filename: String, width: Int, height: Int, createdAt: Date = .now, duration: Double? = nil) {
        self.id = id
        self.mediaType = mediaType
        self.filename = filename
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.duration = duration
    }
}
