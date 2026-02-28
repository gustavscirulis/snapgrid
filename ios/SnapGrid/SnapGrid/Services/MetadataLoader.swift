import Foundation

struct LoadResult {
    let items: [SnapGridItem]
    let skippedCount: Int
}

struct MetadataLoader {
    let metadataDir: URL
    let imagesDir: URL
    let thumbnailsDir: URL

    func loadAllItems() async throws -> LoadResult {
        let fm = FileManager.default

        let contents = try fm.contentsOfDirectory(
            at: metadataDir,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        )

        let jsonFiles = contents.filter { $0.pathExtension == "json" }
        #if DEBUG
        print("[MetadataLoader] Found \(jsonFiles.count) metadata files")
        #endif

        let decoder = JSONDecoder()
        var loadedItems: [SnapGridItem] = []
        var skipped = 0

        for url in jsonFiles {
            // Check if the file is downloaded from iCloud
            if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               let status = resourceValues.ubiquitousItemDownloadingStatus,
               status != .current {
                // File isn't downloaded yet — trigger download but don't wait
                try? fm.startDownloadingUbiquitousItem(at: url)
                skipped += 1
                continue
            }

            guard let data = try? Data(contentsOf: url) else {
                #if DEBUG
                print("[MetadataLoader] Could not read: \(url.lastPathComponent)")
                #endif
                continue
            }

            guard var item = try? decoder.decode(SnapGridItem.self, from: data) else {
                #if DEBUG
                print("[MetadataLoader] Could not decode: \(url.lastPathComponent)")
                #endif
                continue
            }

            let id = url.deletingPathExtension().lastPathComponent
            let ext = item.isVideo ? "mp4" : "png"
            let mediaURL = imagesDir.appendingPathComponent("\(id).\(ext)")

            // Skip orphaned metadata (JSON exists but media file doesn't)
            if !fm.fileExists(atPath: mediaURL.path) {
                #if DEBUG
                print("[MetadataLoader] Media file missing for: \(id), skipping")
                #endif
                continue
            }

            item.mediaURL = mediaURL
            if !item.isVideo {
                item.thumbnailURL = thumbnailsDir.appendingPathComponent("\(id).jpg")
            }

            // Proactively trigger iCloud download of media file
            if let rv = try? mediaURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               let status = rv.ubiquitousItemDownloadingStatus,
               status != .current {
                try? fm.startDownloadingUbiquitousItem(at: mediaURL)
            }

            loadedItems.append(item)
        }

        #if DEBUG
        if skipped > 0 {
            print("[MetadataLoader] Skipped \(skipped) files not yet downloaded from iCloud")
        }
        print("[MetadataLoader] Loaded \(loadedItems.count) items")
        #endif

        let sorted = loadedItems.sorted {
            ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
        }

        return LoadResult(items: sorted, skippedCount: skipped)
    }

    enum LoaderError: LocalizedError {
        case noAccess

        var errorDescription: String? {
            switch self {
            case .noAccess:
                return "No access to SnapGrid folder"
            }
        }
    }
}
