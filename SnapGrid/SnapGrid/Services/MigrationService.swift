import Foundation
import SwiftData

/// Handles one-time migration of media files from Application Support to the iCloud container.
/// Bootstrapping SwiftData from iCloud sidecars (fresh install / database reset) is handled
/// by SyncWatcher.initialSync which runs asynchronously.
enum MigrationService {

    private static let migrationKey = "iCloudMigrationComplete_v1"

    /// Run migration if needed. Call on app launch before starting SyncWatcher.
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        let storage = MediaStorageService.shared

        // Only migrate if we're actually using iCloud
        guard storage.isUsingiCloud else { return }
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldBase = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        let oldMediaDir = oldBase.appendingPathComponent("media", isDirectory: true)

        let hasOldData = fm.fileExists(atPath: oldMediaDir.path) && hasFiles(in: oldMediaDir)
        let hasSwiftDataRecords = (try? context.fetchCount(FetchDescriptor<MediaItem>())) ?? 0 > 0

        if hasOldData && hasSwiftDataRecords {
            // Existing Mac app user — move files from App Support to iCloud container
            migrateFromAppSupport(oldBase: oldBase, context: context)
        }
        // Note: if SwiftData is empty but sidecars exist in iCloud (fresh install or DB reset),
        // SyncWatcher.initialSync handles it asynchronously with UI yielding.

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Migrate from Application Support

    private static func migrateFromAppSupport(oldBase: URL, context: ModelContext) {
        let fm = FileManager.default
        let storage = MediaStorageService.shared
        let sidecarService = MetadataSidecarService.shared

        let oldMediaDir = oldBase.appendingPathComponent("media", isDirectory: true)
        let oldThumbDir = oldBase.appendingPathComponent("thumbnails", isDirectory: true)

        guard let items = try? context.fetch(FetchDescriptor<MediaItem>()) else { return }

        var migrated = 0
        for item in items {
            let oldMediaURL = oldMediaDir.appendingPathComponent(item.filename)
            let newMediaURL = storage.mediaDir.appendingPathComponent(item.filename)

            // Move media file if it exists in old location and not yet in new
            if fm.fileExists(atPath: oldMediaURL.path) && !fm.fileExists(atPath: newMediaURL.path) {
                do {
                    try fm.moveItem(at: oldMediaURL, to: newMediaURL)
                } catch {
                    print("[Migration] Failed to move media \(item.filename): \(error)")
                    continue
                }
            }

            // Move thumbnail
            let oldThumbURL = oldThumbDir.appendingPathComponent("\(item.id).jpg")
            let newThumbURL = storage.thumbnailDir.appendingPathComponent("\(item.id).jpg")
            if fm.fileExists(atPath: oldThumbURL.path) && !fm.fileExists(atPath: newThumbURL.path) {
                try? fm.moveItem(at: oldThumbURL, to: newThumbURL)
            }

            // Write JSON sidecar
            sidecarService.writeSidecar(for: item)
            migrated += 1
        }

        // Write spaces.json
        if let spaces = try? context.fetch(FetchDescriptor<Space>()) {
            sidecarService.writeSpaces(spaces)
        }

        if migrated > 0 {
            print("[Migration] Migrated \(migrated) items from Application Support to iCloud container")
        }

        // Clean up old directories (keep SwiftData store)
        try? fm.removeItem(at: oldMediaDir)
        try? fm.removeItem(at: oldThumbDir)
        let oldQueueDir = oldBase.appendingPathComponent("queue", isDirectory: true)
        try? fm.removeItem(at: oldQueueDir)
        let oldTrashDir = oldBase.appendingPathComponent(".trash", isDirectory: true)
        try? fm.removeItem(at: oldTrashDir)
    }

    // MARK: - Helpers

    private static func hasFiles(in dir: URL, ext: String? = nil) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return false }
        if let ext {
            return files.contains { $0.pathExtension == ext }
        }
        return files.contains { !$0.lastPathComponent.hasPrefix(".") }
    }
}
