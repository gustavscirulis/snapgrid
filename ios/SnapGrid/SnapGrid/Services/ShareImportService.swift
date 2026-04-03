import Foundation

/// Moves media saved by the Share Extension from the App Group staging area
/// into the iCloud container so they sync to the Mac app for analysis.
enum ShareImportService {

    private static let appGroupID = "group.com.snapgrid"

    /// Check the App Group pending directory and move any media + metadata
    /// into the iCloud container. Safe to call multiple times — completed
    /// imports are deleted from the staging area.
    static func importPendingItems(to rootURL: URL) {
        let fm = FileManager.default

        guard let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }

        let pendingDir = containerURL.appendingPathComponent("pending", isDirectory: true)
        let pendingImages = pendingDir.appendingPathComponent("images", isDirectory: true)
        let pendingMetadata = pendingDir.appendingPathComponent("metadata", isDirectory: true)

        guard fm.fileExists(atPath: pendingMetadata.path) else { return }

        let imagesDir = rootURL.appendingPathComponent("images", isDirectory: true)
        let metadataDir = rootURL.appendingPathComponent("metadata", isDirectory: true)

        // Ensure destination directories exist
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)

        // List pending metadata files
        guard let metadataFiles = try? fm.contentsOfDirectory(
            at: pendingMetadata,
            includingPropertiesForKeys: nil
        ) else { return }

        let jsonFiles = metadataFiles.filter { $0.pathExtension == "json" }
        guard !jsonFiles.isEmpty else { return }

        #if DEBUG
        print("[ShareImport] Found \(jsonFiles.count) pending import(s)")
        #endif

        for jsonURL in jsonFiles {
            let id = jsonURL.deletingPathExtension().lastPathComponent

            // Determine file extension from sidecar type field, falling back to .png
            let ext = mediaExtension(for: jsonURL) ?? "png"
            let mediaFilename = "\(id).\(ext)"

            let srcMedia = pendingImages.appendingPathComponent(mediaFilename)
            let dstImage = imagesDir.appendingPathComponent(mediaFilename)
            let dstMetadata = metadataDir.appendingPathComponent(jsonURL.lastPathComponent)

            // Move media file first (SyncWatcher checks for media when sidecar arrives)
            guard fm.fileExists(atPath: srcMedia.path) else {
                #if DEBUG
                print("[ShareImport] Source media missing for \(id) (\(mediaFilename)), skipping")
                #endif
                continue
            }

            do {
                if fm.fileExists(atPath: dstImage.path) {
                    try fm.removeItem(at: dstImage)
                }
                try fm.moveItem(at: srcMedia, to: dstImage)
            } catch {
                #if DEBUG
                print("[ShareImport] Failed to move media \(id): \(error)")
                #endif
                continue
            }

            // Then move metadata sidecar
            do {
                if fm.fileExists(atPath: dstMetadata.path) {
                    try fm.removeItem(at: dstMetadata)
                }
                try fm.moveItem(at: jsonURL, to: dstMetadata)
            } catch {
                #if DEBUG
                print("[ShareImport] Failed to move metadata \(id): \(error)")
                #endif
                continue
            }

            #if DEBUG
            print("[ShareImport] Imported \(id)")
            #endif
        }
    }

    /// Read the sidecar JSON to determine whether this is a video or image.
    static func mediaExtension(for sidecarURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sidecarURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        return type == "video" ? "mp4" : "png"
    }
}
