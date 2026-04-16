import Foundation
import SwiftUI
import SwiftData

@MainActor
class FileSystemManager: ObservableObject {
    /// Shared instance for use by SwiftData computed properties (set on app launch).
    static var shared: FileSystemManager?

    @Published var rootURL: URL?
    @Published var isAccessGranted = false
    @Published var isCheckingAccess = false
    @Published var iCloudContainerActive = false
    @Published var isUsingiCloud = false
    @Published var error: String?

    private let iCloudContainerID = "iCloud.com.SnapGrid"
    private let migrationKey = "localToiCloudMigrationComplete_v1"

    var imagesDir: URL? { rootURL?.appendingPathComponent("images") }
    var metadataDir: URL? { rootURL?.appendingPathComponent("metadata") }
    var thumbnailsDir: URL? { rootURL?.appendingPathComponent("thumbnails") }

    /// Local storage path (used as fallback when iCloud is unavailable)
    var localStorageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SnapGrid", isDirectory: true)
    }

    // MARK: - Access Restoration

    func restoreAccess() {
        isCheckingAccess = true

        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let containerURL = fm.url(forUbiquityContainerIdentifier: self.iCloudContainerID)

            await MainActor.run {
                if let containerURL {
                    let docsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
                    self.rootURL = docsURL
                    self.isUsingiCloud = true
                    self.iCloudContainerActive = true
                } else {
                    // Local fallback — create directory structure and proceed
                    let localRoot = self.localStorageURL
                    let subdirs = [
                        "images", "metadata", "thumbnails",
                        ".trash/images", ".trash/metadata", ".trash/thumbnails"
                    ]
                    for sub in subdirs {
                        try? fm.createDirectory(
                            at: localRoot.appendingPathComponent(sub, isDirectory: true),
                            withIntermediateDirectories: true
                        )
                    }
                    self.rootURL = localRoot
                    self.isUsingiCloud = false
                    self.iCloudContainerActive = false
                }
                self.isAccessGranted = true
                self.error = nil
                self.isCheckingAccess = false
            }
        }
    }

    // MARK: - Silent iCloud Migration

    /// Check if iCloud became available and silently migrate local data.
    /// Safe to call repeatedly — guarded by UserDefaults flag and state checks.
    func checkAndMigrateToiCloud(context: ModelContext) {
        // Only relevant when currently using local storage
        guard !isUsingiCloud else { return }

        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            // Check if iCloud is now available
            guard let containerURL = fm.url(forUbiquityContainerIdentifier: self.iCloudContainerID) else {
                return // Still no iCloud
            }

            let iCloudRoot = containerURL.appendingPathComponent("Documents", isDirectory: true)
            let localRoot = await self.localStorageURL

            // Run migration
            await LocalToiCloudMigrationService.migrate(
                from: localRoot,
                to: iCloudRoot
            )

            // Switch to iCloud
            await MainActor.run {
                self.rootURL = iCloudRoot
                self.isUsingiCloud = true
                self.iCloudContainerActive = true
                print("[FileSystemManager] Switched to iCloud storage")
            }
        }
    }
}
