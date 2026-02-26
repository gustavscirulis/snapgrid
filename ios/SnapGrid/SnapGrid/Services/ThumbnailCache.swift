import UIKit
import AVFoundation

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
                if url.pathExtension.lowercased() == "mp4" {
                    // Video file: extract a frame with AVAssetImageGenerator
                    guard let thumbnail = self?.generateVideoThumbnail(for: url) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
                    self?.cache.setObject(thumbnail, forKey: key, cost: cost)
                    continuation.resume(returning: thumbnail)
                    return
                }

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

    private func generateVideoThumbnail(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("[ThumbnailCache] Failed to generate video thumbnail: \(error)")
            return nil
        }
    }
}
