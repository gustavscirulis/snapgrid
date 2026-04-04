import Foundation

/// Centralizes all sidecar JSON write operations for the iOS app.
/// Uses a merge strategy when the sidecar exists, or creates a complete
/// sidecar from model data when the file hasn't downloaded from iCloud yet.
enum SidecarWriteService {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Update the spaceId field in a media item's sidecar JSON.
    /// Removes the key when spaceId is nil (not NSNull — that was a bug).
    /// Falls back to writing a complete sidecar if the file doesn't exist yet.
    static func writeSpaceId(for item: MediaItem, rootURL: URL) {
        let sidecarURL = rootURL.appendingPathComponent("metadata/\(item.id).json")

        if let existingData = try? Data(contentsOf: sidecarURL),
           var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            // Merge into existing sidecar
            if let spaceId = item.space?.id {
                json["spaceId"] = spaceId
            } else {
                json.removeValue(forKey: "spaceId")
            }

            if let updatedData = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? updatedData.write(to: sidecarURL, options: .atomic)
            }
        } else {
            // File not downloaded yet — write a complete sidecar from model data
            writeFullSidecar(for: item, to: sidecarURL)
        }
    }

    /// Write analysis results back to a media item's sidecar JSON.
    /// Falls back to writing a complete sidecar if the file doesn't exist yet.
    static func writeAnalysis(for item: MediaItem, rootURL: URL) {
        let sidecarURL = rootURL.appendingPathComponent("metadata/\(item.id).json")

        if let existingData = try? Data(contentsOf: sidecarURL),
           var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            // Merge into existing sidecar
            if let result = item.analysisResult {
                json["imageContext"] = result.imageContext
                json["imageSummary"] = result.imageSummary
                json["patterns"] = result.patterns.map { ["name": $0.name, "confidence": $0.confidence] }
                let formatter = ISO8601DateFormatter()
                json["analyzedAt"] = formatter.string(from: result.analyzedAt)
            }

            if let updatedData = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? updatedData.write(to: sidecarURL, options: .atomic)
            }
        } else {
            // File not downloaded yet — write a complete sidecar from model data
            writeFullSidecar(for: item, to: sidecarURL)
        }
    }

    /// Construct and write a complete sidecar JSON from the MediaItem model.
    /// Used as a fallback when the existing sidecar hasn't downloaded from iCloud.
    private static func writeFullSidecar(for item: MediaItem, to url: URL) {
        let sidecar = SidecarMetadata(
            id: item.id,
            type: item.mediaType.rawValue,
            width: item.width,
            height: item.height,
            createdAt: item.createdAt,
            duration: item.duration,
            spaceId: item.space?.id,
            imageContext: item.analysisResult?.imageContext,
            imageSummary: item.analysisResult?.imageSummary,
            patterns: item.analysisResult?.patterns.map { SidecarPattern(name: $0.name, confidence: $0.confidence) },
            sourceURL: item.sourceURL,
            analyzedAt: item.analysisResult?.analyzedAt
        )

        if let data = try? encoder.encode(sidecar) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
