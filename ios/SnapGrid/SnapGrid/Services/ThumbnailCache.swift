import UIKit
import ImageIO
import AVFoundation

/// Actor-based concurrency limiter to replace DispatchSemaphore in async contexts.
private actor ConcurrencyLimiter {
    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) { self.maxConcurrent = maxConcurrent }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        running -= 1
        if !waiters.isEmpty {
            running += 1
            waiters.removeFirst().resume()
        }
    }
}

class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let limiter = ConcurrencyLimiter(maxConcurrent: 4)
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

        let monitor = iCloudDownloadMonitor.shared
        if !monitor.isDownloaded(url) {
            monitor.requestDownload(for: url)
            return nil
        }

        // Throttle concurrent loads using structured concurrency
        await limiter.acquire()
        defer { Task { await limiter.release() } }

        if url.pathExtension.lowercased() == "mp4" {
            guard let thumbnail = generateVideoThumbnail(for: url) else {
                return nil
            }
            let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
            cache.setObject(thumbnail, forKey: key, cost: cost)
            return thumbnail
        }

        let image = downsampledImage(at: url, targetPixelWidth: targetPixelWidth)

        guard let image else {
            return nil
        }

        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Wait for a file to download from iCloud, then load it.
    /// Returns nil only if the timeout expires and the file still can't be loaded.
    func loadImageWhenReady(for url: URL, timeout: TimeInterval = 120, targetPixelWidth: CGFloat = 0) async -> UIImage? {
        if let image = await loadImage(for: url, targetPixelWidth: targetPixelWidth) {
            return image
        }

        await iCloudDownloadMonitor.shared.waitForDownload(of: url, timeout: timeout)
        return await loadImage(for: url, targetPixelWidth: targetPixelWidth)
    }

    func clear() {
        cache.removeAllObjects()
    }

    /// Prefetch thumbnails for a batch of items in the background.
    /// Loads at lower priority so it doesn't block on-screen cells.
    @discardableResult
    func prefetchThumbnails(for items: [SnapGridItem], targetPixelWidth: CGFloat) -> Task<Void, Never> {
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
