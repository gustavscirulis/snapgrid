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

    /// Update the spaceIds field in a media item's sidecar JSON.
    /// Removes both membership keys when the item has no spaces.
    /// Falls back to writing a complete sidecar if the file doesn't exist yet.
    static func writeSpaceMembership(for item: MediaItem, rootURL: URL) {
        updateSidecar(for: item, rootURL: rootURL) { json in
            let spaceIds = item.orderedSpaceIDs
            if spaceIds.isEmpty {
                json.removeValue(forKey: "spaceIds")
                json.removeValue(forKey: "spaceId")
            } else {
                json["spaceIds"] = spaceIds
                json.removeValue(forKey: "spaceId")
            }
        }
    }

    static func writeSpaceId(for item: MediaItem, rootURL: URL) {
        writeSpaceMembership(for: item, rootURL: rootURL)
    }

    /// Write analysis results back to a media item's sidecar JSON.
    /// Falls back to writing a complete sidecar if the file doesn't exist yet.
    static func writeAnalysis(for item: MediaItem, rootURL: URL) {
        updateSidecar(for: item, rootURL: rootURL) { json in
            if let result = item.analysisResult {
                json["imageContext"] = result.imageContext
                json["imageSummary"] = result.imageSummary
                json["patterns"] = result.patterns.map { ["name": $0.name, "confidence": $0.confidence] }
                let formatter = ISO8601DateFormatter()
                json["analyzedAt"] = formatter.string(from: result.analyzedAt)
            }
        }
    }

    // MARK: - Private

    /// Read-modify-write helper: loads existing sidecar JSON, applies the update
    /// closure, and writes back. Falls back to a full sidecar if the file
    /// hasn't downloaded from iCloud yet.
    private static func updateSidecar(
        for item: MediaItem,
        rootURL: URL,
        update: (inout [String: Any]) -> Void
    ) {
        let sidecarURL = rootURL.appendingPathComponent("metadata/\(item.id).json")

        if let existingData = try? Data(contentsOf: sidecarURL),
           var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            update(&json)
            if let updatedData = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? updatedData.write(to: sidecarURL, options: .atomic)
            }
        } else {
            writeFullSidecar(for: item, to: sidecarURL)
        }
    }

    /// Write the full spaces list to spaces.json, mirroring the Mac app's format.
    /// Preserves allSpaceGuidance from UserDefaults so it round-trips through iCloud.
    static func writeSpaces(_ spaces: [Space], rootURL: URL) {
        let sidecars = spaces.map { space in
            SidecarSpace(
                id: space.id,
                name: space.name,
                order: space.order,
                createdAt: space.createdAt,
                customPrompt: space.customPrompt,
                useCustomPrompt: space.useCustomPrompt
            )
        }

        let allGuidance = UserDefaults.standard.string(forKey: "allSpacePrompt")
        let useAllGuidance = UserDefaults.standard.bool(forKey: "useAllSpacePrompt")

        let file = SidecarSpacesFile(
            spaces: sidecars,
            allSpaceGuidance: allGuidance,
            useAllSpaceGuidance: useAllGuidance
        )

        let spacesURL = rootURL.appendingPathComponent("spaces.json")
        if let data = try? encoder.encode(file) {
            try? data.write(to: spacesURL, options: .atomic)
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
            spaceIds: item.orderedSpaceIDs,
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
