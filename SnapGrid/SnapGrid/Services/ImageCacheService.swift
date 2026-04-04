import AppKit

/// In-memory thumbnail cache to avoid repeated disk reads.
/// Uses NSCache which automatically evicts under memory pressure.
final class ImageCacheService: @unchecked Sendable {
    static let shared = ImageCacheService()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 1500
        cache.totalCostLimit = 200 * 1024 * 1024 // 200 MB
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        let cost = image.tiffRepresentation?.count ?? 100_000
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    /// Load a thumbnail for an item, checking cache first, then disk.
    /// Caches the result for future reads. Runs disk I/O on a background thread.
    /// When no pre-generated thumbnail exists, generates and persists one from the
    /// original file to avoid caching full-resolution images in memory.
    func loadThumbnail(id: String, filename: String) async -> NSImage? {
        if let cached = image(forKey: id) {
            return cached
        }

        let loaded: NSImage? = await Task.detached(priority: .utility) {
            let storage = MediaStorageService.shared

            // Fast path: pre-generated thumbnail exists on disk
            if storage.thumbnailExists(id: id) {
                return NSImage(contentsOf: storage.thumbnailURL(id: id))
            }

            // Slow path: load original, generate + persist a thumbnail, return that
            let mediaURL = storage.mediaURL(filename: filename)
            guard let original = NSImage(contentsOf: mediaURL) else { return nil }

            if let _ = try? ThumbnailService.generateThumbnail(from: original, id: id, storage: storage) {
                // Return the newly saved thumbnail (smaller, JPEG-compressed)
                return NSImage(contentsOf: storage.thumbnailURL(id: id))
            }

            // Last resort: generate in-memory thumbnail (not persisted)
            if let thumbData = original.thumbnailData(maxWidth: 800, quality: 0.9) {
                return NSImage(data: thumbData)
            }
            return nil
        }.value

        if let loaded {
            setImage(loaded, forKey: id)
        }
        return loaded
    }
}
