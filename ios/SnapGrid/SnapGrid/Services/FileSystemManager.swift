import Foundation
import SwiftUI

@MainActor
class FileSystemManager: ObservableObject {
    @Published var rootURL: URL?
    @Published var isAccessGranted = false
    @Published var isCheckingAccess = false
    @Published var iCloudContainerActive = false
    @Published var error: String?

    private let iCloudContainerID = "iCloud.com.SnapGrid"

    var imagesDir: URL? { rootURL?.appendingPathComponent("images") }
    var metadataDir: URL? { rootURL?.appendingPathComponent("metadata") }
    var thumbnailsDir: URL? { rootURL?.appendingPathComponent("thumbnails") }

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
                    self.isAccessGranted = true
                    self.iCloudContainerActive = true
                    self.error = nil
                } else {
                    self.error = "iCloud is not available. Please sign in to iCloud in Settings to use SnapGrid."
                }
                self.isCheckingAccess = false
            }
        }
    }
}
