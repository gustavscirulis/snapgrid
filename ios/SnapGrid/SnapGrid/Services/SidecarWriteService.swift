import Foundation

/// Centralizes all sidecar JSON write operations for the iOS app.
/// Merges the previously duplicated writeSidecarSpaceId and updateSidecarSpaceId methods.
enum SidecarWriteService {

    /// Update the spaceId field in a media item's sidecar JSON.
    /// Removes the key when spaceId is nil (not NSNull — that was a bug).
    static func writeSpaceId(for item: MediaItem, rootURL: URL) {
        let sidecarURL = rootURL.appendingPathComponent("metadata/\(item.id).json")

        guard let existingData = try? Data(contentsOf: sidecarURL),
              var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
            return
        }

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
    }

    /// Write analysis results back to a media item's sidecar JSON.
    static func writeAnalysis(for item: MediaItem, rootURL: URL) {
        let sidecarURL = rootURL.appendingPathComponent("metadata/\(item.id).json")

        guard let existingData = try? Data(contentsOf: sidecarURL),
              var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
            return
        }

        if let result = item.analysisResult {
            json["imageContext"] = result.imageContext
            json["imageSummary"] = result.imageSummary
            json["patterns"] = result.patterns.map { ["name": $0.name, "confidence": $0.confidence] }
        }

        if let updatedData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? updatedData.write(to: sidecarURL, options: .atomic)
        }
    }
}
