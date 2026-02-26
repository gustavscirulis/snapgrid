import Foundation
import Combine

/// Centralized monitor for iCloud file downloads.
/// Tracks requested downloads and polls their status, publishing updates
/// when files become available.
class iCloudDownloadMonitor {
    static let shared = iCloudDownloadMonitor()

    /// Publishes file URLs that have just finished downloading
    let fileReady = PassthroughSubject<URL, Never>()

    private var pendingDownloads: Set<URL> = []
    private var pollingTask: Task<Void, Never>?
    private let lock = NSLock()
    private let pollInterval: TimeInterval = 3.0

    private init() {}

    /// Request download of an iCloud file and monitor it.
    func requestDownload(for url: URL) {
        lock.lock()
        let isNew = pendingDownloads.insert(url).inserted
        lock.unlock()

        if isNew {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            startPollingIfNeeded()
        }
    }

    /// Check if a file is currently downloaded/local.
    func isDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.ubiquitousItemDownloadingStatusKey]
        ) else {
            // Can't read resource values — assume local file
            return true
        }
        guard let status = values.ubiquitousItemDownloadingStatus else {
            // No iCloud status — non-iCloud file
            return true
        }
        return status == .current
    }

    private func startPollingIfNeeded() {
        lock.lock()
        let alreadyPolling = pollingTask != nil
        lock.unlock()

        guard !alreadyPolling else { return }

        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 3.0))
                guard let self = self else { break }
                self.checkPendingDownloads()
            }
        }

        lock.lock()
        pollingTask = task
        lock.unlock()
    }

    private func checkPendingDownloads() {
        lock.lock()
        let urls = pendingDownloads
        lock.unlock()

        guard !urls.isEmpty else { return }

        var completed: [URL] = []
        for url in urls {
            if isDownloaded(url) {
                completed.append(url)
            }
        }

        if !completed.isEmpty {
            lock.lock()
            for url in completed {
                pendingDownloads.remove(url)
            }
            let shouldStop = pendingDownloads.isEmpty
            lock.unlock()

            for url in completed {
                fileReady.send(url)
            }

            if shouldStop {
                lock.lock()
                pollingTask?.cancel()
                pollingTask = nil
                lock.unlock()
            }
        }
    }
}
