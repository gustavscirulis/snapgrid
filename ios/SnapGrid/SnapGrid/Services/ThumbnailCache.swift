import UIKit
import Combine

class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.snapgrid.thumbnailcache", qos: .userInitiated, attributes: .concurrent)

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    /// Try to load image immediately. Returns nil if file needs iCloud download.
    func loadImage(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                let monitor = iCloudDownloadMonitor.shared

                // Check if this is an iCloud file that hasn't been downloaded yet
                if !monitor.isDownloaded(url) {
                    monitor.requestDownload(for: url)
                    continuation.resume(returning: nil)
                    return
                }

                // File is local — read it
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }

                self?.cache.setObject(image, forKey: key, cost: data.count)
                continuation.resume(returning: image)
            }
        }
    }

    /// Wait for a file to download from iCloud, then load it.
    /// Returns nil only if the timeout expires.
    func loadImageWhenReady(for url: URL, timeout: TimeInterval = 120) async -> UIImage? {
        // Fast path: try immediate load
        if let image = await loadImage(for: url) {
            return image
        }

        let monitor = iCloudDownloadMonitor.shared
        monitor.requestDownload(for: url)

        // Slow path: wait for the monitor to signal this file is ready
        let resumeLock = NSLock()
        var resumed = false
        var cancellable: AnyCancellable?
        var timeoutTask: Task<Void, Never>?

        func resumeOnce(with image: UIImage?, continuation: CheckedContinuation<UIImage?, Never>) {
            resumeLock.lock()
            guard !resumed else {
                resumeLock.unlock()
                return
            }
            resumed = true
            resumeLock.unlock()
            cancellable?.cancel()
            timeoutTask?.cancel()
            continuation.resume(returning: image)
        }

        return await withCheckedContinuation { continuation in
            // Handle task cancellation (e.g. view scrolled off screen)
            if Task.isCancelled {
                continuation.resume(returning: nil)
                return
            }

            cancellable = monitor.fileReady
                .filter { $0.absoluteString == url.absoluteString }
                .first()
                .receive(on: DispatchQueue.global(qos: .userInitiated))
                .sink { [weak self] readyURL in
                    guard let self = self else {
                        resumeOnce(with: nil, continuation: continuation)
                        return
                    }
                    Task {
                        let image = await self.loadImage(for: readyURL)
                        resumeOnce(with: image, continuation: continuation)
                    }
                }

            timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                if Task.isCancelled {
                    resumeOnce(with: nil, continuation: continuation)
                    return
                }
                // One last attempt before giving up
                let lastTry = await self.loadImage(for: url)
                resumeOnce(with: lastTry, continuation: continuation)
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
    }
}
