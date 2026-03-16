import AppKit

/// In-memory thumbnail cache to avoid repeated disk reads.
/// Uses NSCache which automatically evicts under memory pressure.
final class ImageCacheService: @unchecked Sendable {
    static let shared = ImageCacheService()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 500
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}
