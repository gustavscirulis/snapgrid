import Foundation

/// Moves images saved by the Share Extension from the App Group staging area
/// into the iCloud container so they sync to the Mac app for analysis.
enum ShareImportService {

    private static let appGroupID = "group.com.snapgrid"

    /// Check the App Group pending directory and move any images + metadata
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
            let imageFilename = "\(id).png"

            let srcImage = pendingImages.appendingPathComponent(imageFilename)
            let dstImage = imagesDir.appendingPathComponent(imageFilename)
            let dstMetadata = metadataDir.appendingPathComponent(jsonURL.lastPathComponent)

            // Move image first (SyncWatcher checks for media when sidecar arrives)
            guard fm.fileExists(atPath: srcImage.path) else {
                #if DEBUG
                print("[ShareImport] Source image missing for \(id), skipping")
                #endif
                continue
            }

            do {
                if fm.fileExists(atPath: dstImage.path) {
                    try fm.removeItem(at: dstImage)
                }
                try fm.moveItem(at: srcImage, to: dstImage)
            } catch {
                #if DEBUG
                print("[ShareImport] Failed to move image \(id): \(error)")
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
}
