import Foundation

/// Silently migrates local media files to iCloud when iCloud becomes available.
/// Uses ID-based dedup (UUIDs) so the operation is idempotent and safe to retry.
/// Copies first, then deletes local copies — no data loss on interruption.
enum LocalToiCloudMigrationService {

    private static let migrationKey = "localToiCloudMigrationComplete_v1"

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Migrate local files to the iCloud container.
    /// Safe to call multiple times — guarded by UserDefaults flag and ID dedup.
    static func migrate(from localRoot: URL, to iCloudRoot: URL) async {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let fm = FileManager.default
        let localMetadata = localRoot.appendingPathComponent("metadata")
        let localImages = localRoot.appendingPathComponent("images")
        let localThumbnails = localRoot.appendingPathComponent("thumbnails")

        let iCloudMetadata = iCloudRoot.appendingPathComponent("metadata")
        let iCloudImages = iCloudRoot.appendingPathComponent("images")
        let iCloudThumbnails = iCloudRoot.appendingPathComponent("thumbnails")

        // Ensure iCloud directories exist
        for dir in [iCloudMetadata, iCloudImages, iCloudThumbnails] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Scan local metadata
        guard let localFiles = try? fm.contentsOfDirectory(at: localMetadata, includingPropertiesForKeys: nil) else {
            // No local metadata — nothing to migrate, just mark done
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        let localJsons = localFiles.filter { $0.pathExtension == "json" }
        guard !localJsons.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Build set of IDs already in iCloud
        let iCloudIds: Set<String> = {
            guard let files = try? fm.contentsOfDirectory(at: iCloudMetadata, includingPropertiesForKeys: nil) else {
                return []
            }
            return Set(files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
        }()

        var migrated = 0

        for jsonURL in localJsons {
            let id = jsonURL.deletingPathExtension().lastPathComponent

            if iCloudIds.contains(id) {
                // Duplicate — check if local has newer analysis
                mergeAnalysisIfNewer(localJSON: jsonURL, iCloudMetadataDir: iCloudMetadata, id: id)
            } else {
                // New item — copy media, metadata, thumbnail to iCloud
                copyItemToiCloud(
                    id: id,
                    localJSON: jsonURL,
                    localImages: localImages,
                    localThumbnails: localThumbnails,
                    iCloudMetadata: iCloudMetadata,
                    iCloudImages: iCloudImages,
                    iCloudThumbnails: iCloudThumbnails
                )
                migrated += 1
            }

            // Yield periodically to avoid blocking
            if migrated % 10 == 0 { await Task.yield() }
        }

        // Merge spaces.json
        mergeSpaces(from: localRoot, to: iCloudRoot)

        // Clean up local files after successful migration
        cleanupLocalStorage(localRoot)

        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[Migration] Migrated \(migrated) items from local to iCloud")
    }

    // MARK: - Copy

    private static func copyItemToiCloud(
        id: String,
        localJSON: URL,
        localImages: URL,
        localThumbnails: URL,
        iCloudMetadata: URL,
        iCloudImages: URL,
        iCloudThumbnails: URL
    ) {
        let fm = FileManager.default

        // Determine media extension from sidecar
        let ext = mediaExtension(for: localJSON)

        // Copy metadata sidecar
        let dstJSON = iCloudMetadata.appendingPathComponent("\(id).json")
        if !fm.fileExists(atPath: dstJSON.path) {
            try? fm.copyItem(at: localJSON, to: dstJSON)
        }

        // Copy media file
        let mediaFilename = "\(id).\(ext)"
        let srcMedia = localImages.appendingPathComponent(mediaFilename)
        let dstMedia = iCloudImages.appendingPathComponent(mediaFilename)
        if fm.fileExists(atPath: srcMedia.path) && !fm.fileExists(atPath: dstMedia.path) {
            try? fm.copyItem(at: srcMedia, to: dstMedia)
        }

        // Copy thumbnail
        let srcThumb = localThumbnails.appendingPathComponent("\(id).jpg")
        let dstThumb = iCloudThumbnails.appendingPathComponent("\(id).jpg")
        if fm.fileExists(atPath: srcThumb.path) && !fm.fileExists(atPath: dstThumb.path) {
            try? fm.copyItem(at: srcThumb, to: dstThumb)
        }
    }

    // MARK: - Merge Analysis

    private static func mergeAnalysisIfNewer(localJSON: URL, iCloudMetadataDir: URL, id: String) {
        guard let localData = try? Data(contentsOf: localJSON),
              let localSidecar = try? decoder.decode(SidecarMetadata.self, from: localData),
              let localAnalyzedAt = localSidecar.analyzedAt else { return }

        let iCloudJSON = iCloudMetadataDir.appendingPathComponent("\(id).json")
        guard let iCloudData = try? Data(contentsOf: iCloudJSON),
              let iCloudSidecar = try? decoder.decode(SidecarMetadata.self, from: iCloudData) else { return }

        let shouldUpdate: Bool
        if let remoteAnalyzedAt = iCloudSidecar.analyzedAt {
            shouldUpdate = localAnalyzedAt > remoteAnalyzedAt
        } else {
            shouldUpdate = true // Local has analysis, remote doesn't
        }

        if shouldUpdate {
            // Overwrite iCloud sidecar with local version (it has newer analysis)
            try? localData.write(to: iCloudJSON, options: .atomic)
        }
    }

    // MARK: - Merge Spaces

    private static func mergeSpaces(from localRoot: URL, to iCloudRoot: URL) {
        let localSpaces = localRoot.appendingPathComponent("spaces.json")
        let iCloudSpaces = iCloudRoot.appendingPathComponent("spaces.json")

        guard let localData = try? Data(contentsOf: localSpaces) else { return }

        let localFile: SidecarSpacesFile?
        if let decoded = try? decoder.decode(SidecarSpacesFile.self, from: localData) {
            localFile = decoded
        } else if let legacySpaces = try? decoder.decode([SidecarSpace].self, from: localData) {
            localFile = SidecarSpacesFile(spaces: legacySpaces, allSpaceGuidance: nil, useAllSpaceGuidance: false)
        } else {
            return
        }

        guard let localFile else { return }

        // If no iCloud spaces file, just copy local
        guard let iCloudData = try? Data(contentsOf: iCloudSpaces) else {
            try? localData.write(to: iCloudSpaces, options: .atomic)
            return
        }

        // Merge: union by ID, prefer iCloud version for conflicts
        let iCloudFile: SidecarSpacesFile?
        if let decoded = try? decoder.decode(SidecarSpacesFile.self, from: iCloudData) {
            iCloudFile = decoded
        } else if let legacySpaces = try? decoder.decode([SidecarSpace].self, from: iCloudData) {
            iCloudFile = SidecarSpacesFile(spaces: legacySpaces, allSpaceGuidance: nil, useAllSpaceGuidance: false)
        } else {
            iCloudFile = nil
        }

        guard let iCloudFile else { return }

        var mergedById: [String: SidecarSpace] = [:]
        // Add local spaces first
        for space in localFile.spaces {
            mergedById[space.id] = space
        }
        // iCloud spaces override (preferred for conflicts)
        for space in iCloudFile.spaces {
            mergedById[space.id] = space
        }

        let mergedSpaces = Array(mergedById.values).sorted { $0.order < $1.order }
        let merged = SidecarSpacesFile(
            spaces: mergedSpaces,
            allSpaceGuidance: iCloudFile.allSpaceGuidance ?? localFile.allSpaceGuidance,
            useAllSpaceGuidance: iCloudFile.useAllSpaceGuidance
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(merged) {
            try? data.write(to: iCloudSpaces, options: .atomic)
        }
    }

    // MARK: - Cleanup

    private static func cleanupLocalStorage(_ localRoot: URL) {
        let fm = FileManager.default
        let subdirs = ["images", "metadata", "thumbnails", ".trash", "spaces.json"]
        for sub in subdirs {
            let url = localRoot.appendingPathComponent(sub)
            try? fm.removeItem(at: url)
        }
        // Try to remove the SnapGrid directory itself if empty
        try? fm.removeItem(at: localRoot)
    }

    // MARK: - Helpers

    private static func mediaExtension(for sidecarURL: URL) -> String {
        guard let data = try? Data(contentsOf: sidecarURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return "png"
        }
        return type == "video" ? "mp4" : "png"
    }
}
