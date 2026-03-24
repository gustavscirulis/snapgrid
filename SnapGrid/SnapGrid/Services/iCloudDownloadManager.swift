import Foundation

/// Scans for iCloud-evicted files and triggers downloads.
/// Uses URLResourceValues (the official iCloud API) to detect download status
/// rather than scanning for .icloud placeholder files, which isn't reliable.
@Observable
@MainActor
final class iCloudDownloadManager {
    static let shared = iCloudDownloadManager()

    private(set) var totalFiles = 0
    private(set) var downloadedFiles = 0
    private(set) var isDownloading = false

    private var pollTask: Task<Void, Never>?

    private init() {}

    /// Scan directories for not-downloaded files and trigger downloads for all of them.
    func downloadAll() {
        guard !isDownloading else { return }
        guard MediaStorageService.shared.isUsingiCloud else { return }

        isDownloading = true
        downloadedFiles = 0

        let storage = MediaStorageService.shared
        let dirs = [storage.mediaDir, storage.thumbnailDir]

        let evictedURLs = findEvictedFiles(in: dirs)
        totalFiles = evictedURLs.count

        if evictedURLs.isEmpty {
            isDownloading = false
            return
        }

        let fm = FileManager.default
        for url in evictedURLs {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }

        // Poll until all downloads complete
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }

                let remaining = findEvictedFiles(in: dirs)
                downloadedFiles = totalFiles - remaining.count

                if remaining.isEmpty {
                    break
                }
            }
            isDownloading = false
        }
    }

    /// Stop any in-progress download polling.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isDownloading = false
    }

    /// Check how many files are currently evicted (for display without triggering downloads).
    func countEvicted() -> Int {
        guard MediaStorageService.shared.isUsingiCloud else { return 0 }
        let storage = MediaStorageService.shared
        return findEvictedFiles(in: [storage.mediaDir, storage.thumbnailDir]).count
    }

    // MARK: - Private

    /// Find files that are not downloaded locally using URLResourceValues.
    /// Checks both real files (ubiquitousItemDownloadingStatus) and .icloud placeholders.
    private nonisolated func findEvictedFiles(in directories: [URL]) -> [URL] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        var evicted: [URL] = []

        for dir in directories {
            // Check real files that exist but aren't fully downloaded
            if let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            ) {
                for file in files {
                    guard let values = try? file.resourceValues(forKeys: keys) else { continue }
                    if values.isUbiquitousItem == true,
                       values.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
                        evicted.append(file)
                    }
                }
            }

            // Also check .icloud placeholder files (hidden, start with ".")
            if let allFiles = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                for file in allFiles {
                    let name = file.lastPathComponent
                    if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                        // Parse real filename from placeholder: ".originalName.icloud" → "originalName"
                        let realName = String(name.dropFirst().dropLast(".icloud".count))
                        let realURL = dir.appendingPathComponent(realName)
                        if !evicted.contains(realURL) {
                            evicted.append(realURL)
                        }
                    }
                }
            }
        }

        return evicted
    }
}
