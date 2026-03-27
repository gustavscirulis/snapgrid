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
        guard pollingTask == nil else {
            lock.unlock()
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 3.0))
                guard let self = self else { break }
                self.checkPendingDownloads()
            }
        }
        pollingTask = task
        lock.unlock()
    }

    /// Wait for a specific file to finish downloading from iCloud.
    /// Returns when the file is ready or the timeout expires.
    func waitForDownload(of url: URL, timeout: TimeInterval = 120) async {
        if isDownloaded(url) { return }
        requestDownload(for: url)

        let resumeLock = NSLock()
        var resumed = false
        var cancellable: AnyCancellable?
        var timeoutTask: Task<Void, Never>?

        func resumeOnce(_ continuation: CheckedContinuation<Void, Never>) {
            resumeLock.lock()
            guard !resumed else { resumeLock.unlock(); return }
            resumed = true
            resumeLock.unlock()
            cancellable?.cancel()
            timeoutTask?.cancel()
            continuation.resume()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if Task.isCancelled {
                continuation.resume()
                return
            }

            cancellable = fileReady
                .filter { $0.absoluteString == url.absoluteString }
                .first()
                .sink { _ in resumeOnce(continuation) }

            timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                resumeOnce(continuation)
            }
        }
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
