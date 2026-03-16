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
}
