import UIKit

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

    func loadImage(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                let fm = FileManager.default

                // Check if this is an iCloud file that hasn't been downloaded yet
                if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                   let status = resourceValues.ubiquitousItemDownloadingStatus,
                   status != .current {
                    // Trigger download in background, return nil for now
                    try? fm.startDownloadingUbiquitousItem(at: url)
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

    func clear() {
        cache.removeAllObjects()
    }
}
