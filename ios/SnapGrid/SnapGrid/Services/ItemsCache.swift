import Foundation

/// Persists the loaded items list to disk so subsequent launches can restore the grid instantly.
actor ItemsCache {
    static let shared = ItemsCache()

    private let cacheFileURL: URL

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheFileURL = cachesDir.appendingPathComponent("items_manifest.json")
    }

    // MARK: - Public

    /// Save items to disk after a successful full load.
    func save(items: [SnapGridItem]) {
        let entries = items.map { item in
            CachedItemEntry(
                id: item.id,
                type: item.type,
                width: item.width,
                height: item.height,
                createdAt: item.createdAt,
                title: item.title,
                description: item.description,
                patterns: item.patterns,
                imageContext: item.imageContext,
                spaceId: item.spaceId,
                duration: item.duration
            )
        }
        let manifest = CachedItemManifest(entries: entries)
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[ItemsCache] Failed to save: \(error)")
            #endif
        }
    }

    /// Load cached items and rehydrate their file URLs using the current directory paths.
    /// Returns nil if no cache exists.
    func loadCached(imagesDir: URL, thumbnailsDir: URL) -> [SnapGridItem]? {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let manifest = try JSONDecoder().decode(CachedItemManifest.self, from: data)
            let items = manifest.entries.map { entry -> SnapGridItem in
                var item = SnapGridItem(
                    type: entry.type,
                    width: entry.width,
                    height: entry.height,
                    createdAt: entry.createdAt,
                    title: entry.title,
                    description: entry.description,
                    patterns: entry.patterns,
                    imageContext: entry.imageContext,
                    spaceId: entry.spaceId,
                    duration: entry.duration
                )
                item.id = entry.id
                let ext = item.isVideo ? "mp4" : "png"
                item.mediaURL = imagesDir.appendingPathComponent("\(entry.id).\(ext)")
                if !item.isVideo {
                    item.thumbnailURL = thumbnailsDir.appendingPathComponent("\(entry.id).jpg")
                }
                return item
            }
            return items.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        } catch {
            #if DEBUG
            print("[ItemsCache] Failed to load: \(error)")
            #endif
            return nil
        }
    }

    /// Invalidate the cache.
    func clear() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}

// MARK: - Cache Serialization Types

private struct CachedItemManifest: Codable {
    let entries: [CachedItemEntry]
}

private struct CachedItemEntry: Codable {
    let id: String
    let type: String
    let width: Int
    let height: Int
    let createdAt: String
    var title: String?
    var description: String?
    var patterns: [PatternTag]?
    var imageContext: String?
    var spaceId: String?
    var duration: Double?
}
