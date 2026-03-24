import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class FileSystemManager: ObservableObject {
    @Published var rootURL: URL?
    @Published var isAccessGranted = false
    @Published var isCheckingAccess = false
    @Published var iCloudContainerActive = false
    @Published var error: String?

    private let bookmarkKey = "snapgrid_folder_bookmark"
    private let iCloudContainerID = "iCloud.com.SnapGrid"

    var imagesDir: URL? { rootURL?.appendingPathComponent("images") }
    var metadataDir: URL? { rootURL?.appendingPathComponent("metadata") }
    var thumbnailsDir: URL? { rootURL?.appendingPathComponent("thumbnails") }

    // MARK: - Access Restoration

    func restoreAccess() {
        isCheckingAccess = true

        // Try iCloud container on a background thread (can block)
        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let containerURL = fm.url(forUbiquityContainerIdentifier: self.iCloudContainerID)

            await MainActor.run {
                if let containerURL {
                    let docsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
                    self.rootURL = docsURL
                    self.isAccessGranted = true
                    self.iCloudContainerActive = true
                    self.error = nil
                } else {
                    // iCloud unavailable — fall back to bookmark
                    self.restoreBookmark()
                }
                self.isCheckingAccess = false
            }
        }
    }

    // MARK: - Bookmark Persistence

    private func restoreBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                bookmarkDataIsStale: &isStale
            )

            guard url.startAccessingSecurityScopedResource() else {
                self.error = "Could not access the SnapGrid folder. Please re-select it."
                return
            }

            if isStale {
                saveBookmark(for: url)
            }

            self.rootURL = url
            self.isAccessGranted = true
            self.error = nil
        } catch {
            self.error = "Folder access expired. Please re-select your SnapGrid folder."
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            self.rootURL = url
            self.isAccessGranted = true
            self.error = nil
        } catch {
            self.error = "Failed to save folder access: \(error.localizedDescription)"
        }
    }

    func grantAccess(to url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            self.error = "Could not access the selected folder."
            return
        }

        // Validate this is a SnapGrid folder
        let fm = FileManager.default
        let hasImages = fm.fileExists(atPath: url.appendingPathComponent("images").path)
        let hasMetadata = fm.fileExists(atPath: url.appendingPathComponent("metadata").path)

        guard hasImages && hasMetadata else {
            url.stopAccessingSecurityScopedResource()
            self.error = "This doesn't look like a SnapGrid folder. It should contain 'images' and 'metadata' directories."
            return
        }

        saveBookmark(for: url)
    }

    func disconnect() {
        if iCloudContainerActive {
            iCloudContainerActive = false
        } else if let url = rootURL {
            url.stopAccessingSecurityScopedResource()
        }
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        self.rootURL = nil
        self.isAccessGranted = false
    }
}
