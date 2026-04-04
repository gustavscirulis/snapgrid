import AVFoundation
import Foundation
import SwiftData

enum DataCleanupService {

    private static let videoDimensionsMigratedKey = "videoDimensionsMigrated_v1"

    /// One-time migration: re-derive video dimensions from poster frames
    /// so that stored width/height matches the true display aspect ratio.
    @MainActor
    static func migrateVideoDimensions(context: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: videoDimensionsMigratedKey) else { return }

        guard let items = try? context.fetch(FetchDescriptor<MediaItem>()) else { return }
        let videos = items.filter { $0.isVideo }
        guard !videos.isEmpty else {
            UserDefaults.standard.set(true, forKey: videoDimensionsMigratedKey)
            return
        }

        var updated = 0
        let storage = MediaStorageService.shared

        for video in videos {
            let url = storage.mediaURL(filename: video.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: url),
               let pixelSize = posterFrame.pixelSize,
               Int(pixelSize.width) > 0, Int(pixelSize.height) > 0 {
                let newW = Int(pixelSize.width)
                let newH = Int(pixelSize.height)
                if newW != video.width || newH != video.height {
                    video.width = newW
                    video.height = newH
                    updated += 1
                }
                // Also regenerate thumbnail to ensure it matches
                _ = try? ThumbnailService.generateThumbnail(from: posterFrame, id: video.id)
            }
        }

        if updated > 0 {
            context.saveOrLog()
            print("[DataCleanup] Migrated dimensions for \(updated) videos")
        }

        UserDefaults.standard.set(true, forKey: videoDimensionsMigratedKey)
    }

    /// Remove SwiftData records whose media files no longer exist on disk.
    @MainActor
    static func cleanOrphanedRecords(context: ModelContext) {
        let storage = MediaStorageService.shared
        let fm = FileManager.default

        guard let items = try? context.fetch(FetchDescriptor<MediaItem>()) else { return }

        var removed = 0
        for item in items {
            let mediaURL = storage.mediaURL(filename: item.filename)
            let mediaPath = mediaURL.path
            if !fm.fileExists(atPath: mediaPath) {
                // Check for iCloud placeholder before considering orphaned —
                // evicted files exist as .filename.icloud in the same directory
                let placeholderName = ".\(item.filename).icloud"
                let placeholderURL = mediaURL.deletingLastPathComponent().appendingPathComponent(placeholderName)
                if fm.fileExists(atPath: placeholderURL.path) {
                    continue  // File is evicted by iCloud, not truly missing
                }
                context.delete(item)
                removed += 1
            }
        }

        if removed > 0 {
            context.saveOrLog()
            print("[DataCleanup] Removed \(removed) orphaned records")
        }

        // Clean up AnalysisResult records that lost their parent MediaItem
        if let allResults = try? context.fetch(FetchDescriptor<AnalysisResult>()) {
            let itemResults = Set(items.compactMap { $0.analysisResult?.persistentModelID })
            var orphanedResults = 0
            for result in allResults {
                if !itemResults.contains(result.persistentModelID) {
                    context.delete(result)
                    orphanedResults += 1
                }
            }
            if orphanedResults > 0 {
                context.saveOrLog()
                print("[DataCleanup] Removed \(orphanedResults) orphaned AnalysisResult records")
            }
        }
    }

    /// Remove sidecar JSON files from metadata/ whose media file no longer exists.
    /// This prevents "Media file not found" warnings on every launch.
    static func cleanOrphanedSidecars() {
        let storage = MediaStorageService.shared
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: storage.metadataDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let allExtensions = SupportedMedia.allExtensions

        var removed = 0
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent

            // Check if any media file exists for this ID (any extension)
            let hasMedia = allExtensions.contains { ext in
                let mediaURL = storage.mediaDir.appendingPathComponent("\(id).\(ext)")
                if fm.fileExists(atPath: mediaURL.path) { return true }
                // Check iCloud placeholder
                let placeholder = storage.mediaDir.appendingPathComponent(".\(id).\(ext).icloud")
                return fm.fileExists(atPath: placeholder.path)
            }

            if !hasMedia {
                try? fm.removeItem(at: file)
                // Also clean up the thumbnail if it exists
                let thumbURL = storage.thumbnailDir.appendingPathComponent("\(id).jpg")
                try? fm.removeItem(at: thumbURL)
                removed += 1
            }
        }

        if removed > 0 {
            print("[DataCleanup] Removed \(removed) orphaned sidecar files")
        }
    }

    /// Delete the SwiftData store entirely and return true if recovery was needed.
    /// Call this when the store is corrupted (e.g. from a cancelled import).
    @MainActor
    static func deleteCorruptedStore() -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let snapGridDir = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        let storeURL = snapGridDir.appendingPathComponent("default.store")
        let fm = FileManager.default

        // Delete all store-related files (main store + WAL + SHM)
        var deleted = false
        for ext in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + ext)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
                deleted = true
            }
        }
        if deleted {
            print("[DataCleanup] Deleted corrupted store files")
        }
        return deleted
    }
}
