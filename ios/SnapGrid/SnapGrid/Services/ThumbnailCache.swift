import UIKit
import ImageIO
import AVFoundation
import Combine

class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let loadSemaphore = DispatchSemaphore(value: 4)
    private let ioQueue = DispatchQueue(label: "com.snapgrid.thumbnailcache", qos: .userInitiated, attributes: .concurrent)
    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    /// Try to load image immediately, downsampled to targetPixelWidth.
    /// Returns nil if file needs iCloud download.
    func loadImage(for url: URL, targetPixelWidth: CGFloat = 0) async -> UIImage? {
        let key = cacheKey(for: url, targetPixelWidth: targetPixelWidth)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                let monitor = iCloudDownloadMonitor.shared

                if !monitor.isDownloaded(url) {
                    monitor.requestDownload(for: url)
                    continuation.resume(returning: nil)
                    return
                }

                // Throttle concurrent loads
                self.loadSemaphore.wait()
                defer { self.loadSemaphore.signal() }

                if url.pathExtension.lowercased() == "mp4" {
                    guard let thumbnail = self.generateVideoThumbnail(for: url) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
                    self.cache.setObject(thumbnail, forKey: key, cost: cost)
                    continuation.resume(returning: thumbnail)
                    return
                }

                let image: UIImage?
                if targetPixelWidth > 0 {
                    image = self.downsampledImage(at: url, targetPixelWidth: targetPixelWidth)
                } else {
                    image = self.downsampledImage(at: url, targetPixelWidth: 0)
                }

                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }

                let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
                self.cache.setObject(image, forKey: key, cost: cost)
                continuation.resume(returning: image)
            }
        }
    }

    /// Wait for a file to download from iCloud, then load it.
    /// Returns nil only if the timeout expires.
    func loadImageWhenReady(for url: URL, timeout: TimeInterval = 120, targetPixelWidth: CGFloat = 0) async -> UIImage? {
        if let image = await loadImage(for: url, targetPixelWidth: targetPixelWidth) {
            return image
        }

        let monitor = iCloudDownloadMonitor.shared
        monitor.requestDownload(for: url)

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
                        let image = await self.loadImage(for: readyURL, targetPixelWidth: targetPixelWidth)
                        resumeOnce(with: image, continuation: continuation)
                    }
                }

            timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                if Task.isCancelled {
                    resumeOnce(with: nil, continuation: continuation)
                    return
                }
                let lastTry = await self.loadImage(for: url, targetPixelWidth: targetPixelWidth)
                resumeOnce(with: lastTry, continuation: continuation)
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
    }

    /// Prefetch thumbnails for a batch of items in the background.
    /// Loads at lower priority so it doesn't block on-screen cells.
    func prefetchThumbnails(for items: [SnapGridItem], targetPixelWidth: CGFloat) {
        Task.detached(priority: .utility) {
            for item in items {
                if Task.isCancelled { break }
                // Try thumbnail file first, then media file
                if let thumbURL = item.thumbnailURL {
                    _ = await self.loadImage(for: thumbURL, targetPixelWidth: targetPixelWidth)
                } else if let mediaURL = item.mediaURL {
                    _ = await self.loadImage(for: mediaURL, targetPixelWidth: targetPixelWidth)
                }
            }
        }
    }

    // MARK: - Private

    private func cacheKey(for url: URL, targetPixelWidth: CGFloat) -> NSString {
        if targetPixelWidth > 0 {
            return "\(url.absoluteString)@\(Int(targetPixelWidth))w" as NSString
        }
        return url.absoluteString as NSString
    }

    /// Decode an image downsampled to the target pixel width using ImageIO.
    /// Pass 0 for full resolution.
    private func downsampledImage(at url: URL, targetPixelWidth: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let maxPixelSize: Int
        if targetPixelWidth > 0 {
            maxPixelSize = Int(targetPixelWidth)
        } else {
            // Full resolution — still use ImageIO for memory-efficient decoding
            maxPixelSize = 0
        }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        if maxPixelSize > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func generateVideoThumbnail(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            #if DEBUG
            print("[ThumbnailCache] Failed to generate video thumbnail: \(error)")
            #endif
            return nil
        }
    }
}
