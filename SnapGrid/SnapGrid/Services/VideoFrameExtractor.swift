import AVFoundation
import AppKit

enum VideoFrameExtractor {

    /// Extract a single frame at a given time fraction (0.0 - 1.0) of the video duration
    static func extractFrame(from url: URL, at fraction: Double) async throws -> NSImage {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let time = CMTime(seconds: durationSeconds * fraction, preferredTimescale: 600)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1920, height: 1920)

        let cgImage = try await generator.image(at: time).image
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Extract poster frame (at 0%)
    static func extractPosterFrame(from url: URL) async throws -> NSImage {
        try await extractFrame(from: url, at: 0.0)
    }

    /// Extract frames for AI analysis (at 33% and 66%)
    static func extractAnalysisFrames(from url: URL) async throws -> [NSImage] {
        async let frame1 = extractFrame(from: url, at: 0.33)
        async let frame2 = extractFrame(from: url, at: 0.66)
        return try await [frame1, frame2]
    }

    /// Get video dimensions and duration
    static func getVideoInfo(from url: URL) async throws -> (width: Int, height: Int, duration: Double) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let track = tracks.first else {
            throw VideoError.noVideoTrack
        }

        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformedSize = size.applying(transform)

        return (
            width: Int(abs(transformedSize.width)),
            height: Int(abs(transformedSize.height)),
            duration: CMTimeGetSeconds(duration)
        )
    }

    enum VideoError: LocalizedError {
        case noVideoTrack

        var errorDescription: String? {
            "No video track found"
        }
    }
}
