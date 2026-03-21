import Foundation
import SwiftData

enum DataCleanupService {

    /// Remove SwiftData records whose media files no longer exist on disk.
    @MainActor
    static func cleanOrphanedRecords(context: ModelContext) {
        let storage = MediaStorageService.shared
        let fm = FileManager.default

        guard let items = try? context.fetch(FetchDescriptor<MediaItem>()) else { return }

        var removed = 0
        for item in items {
            let mediaPath = storage.mediaURL(filename: item.filename).path
            if !fm.fileExists(atPath: mediaPath) {
                context.delete(item)
                removed += 1
            }
        }

        if removed > 0 {
            try? context.save()
            print("[DataCleanup] Removed \(removed) orphaned records")
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
