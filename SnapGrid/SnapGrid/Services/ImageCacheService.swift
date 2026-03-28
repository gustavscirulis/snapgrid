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

    /// Load a thumbnail for an item, checking cache first, then disk.
    /// Caches the result for future reads. Runs disk I/O on a background thread.
    func loadThumbnail(id: String, filename: String) async -> NSImage? {
        if let cached = image(forKey: id) {
            return cached
        }

        let loaded: NSImage? = await Task.detached(priority: .utility) {
            let storage = MediaStorageService.shared
            let url = storage.thumbnailExists(id: id)
                ? storage.thumbnailURL(id: id)
                : storage.mediaURL(filename: filename)
            return NSImage(contentsOf: url)
        }.value

        if let loaded {
            setImage(loaded, forKey: id)
        }
        return loaded
    }
}
