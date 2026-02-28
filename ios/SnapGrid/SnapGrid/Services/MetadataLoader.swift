import Foundation

struct LoadResult {
    let items: [SnapGridItem]
    let skippedCount: Int
}

/// Progressive update emitted during streaming load.
struct LoadUpdate {
    let items: [SnapGridItem]
    let skippedCount: Int
}

struct MetadataLoader {
    let metadataDir: URL
    let imagesDir: URL
    let thumbnailsDir: URL

    /// Stream items progressively in batches so the UI can update as items are decoded.
    func loadItemsProgressively(batchSize: Int = 20) -> AsyncThrowingStream<LoadUpdate, Error> {
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let fm = FileManager.default

                    // Don't skip hidden files — iCloud placeholders are hidden (.filename.icloud)
                    let contents = try fm.contentsOfDirectory(
                        at: metadataDir,
                        includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
                        options: []
                    )

                    // Match both downloaded .json files and iCloud placeholders (.json.icloud)
                    let jsonFiles = contents.filter { url in
                        let name = url.lastPathComponent
                        return name.hasSuffix(".json") || name.hasSuffix(".json.icloud")
                    }
                    #if DEBUG
                    print("[MetadataLoader] Found \(jsonFiles.count) metadata files")
                    #endif

                    let decoder = JSONDecoder()
                    var loadedItems: [SnapGridItem] = []
                    var skipped = 0
                    var lastYieldCount = 0

                    for url in jsonFiles {
                        // iCloud placeholder files (.json.icloud) can't be read directly.
                        // Trigger download and skip — the 15s rescan will pick them up.
                        let fileName = url.lastPathComponent
                        if fileName.hasSuffix(".json.icloud") {
                            var realName = String(fileName.dropLast(".icloud".count))
                            if realName.hasPrefix(".") {
                                realName = String(realName.dropFirst())
                            }
                            let realURL = url.deletingLastPathComponent().appendingPathComponent(realName)
                            try? fm.startDownloadingUbiquitousItem(at: realURL)
                            skipped += 1
                            continue
                        }

                        // Check if the JSON file is downloaded from iCloud
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
                        item.id = id
                        let ext = item.isVideo ? "mp4" : "png"
                        let mediaURL = imagesDir.appendingPathComponent("\(id).\(ext)")

                        // Check if media exists locally, as iCloud placeholder, or in iCloud
                        let iCloudPlaceholder = imagesDir.appendingPathComponent(".\(id).\(ext).icloud")
                        if fm.fileExists(atPath: mediaURL.path) {
                            // File is downloaded locally — nothing to do
                        } else if fm.fileExists(atPath: iCloudPlaceholder.path) {
                            // File exists as iCloud placeholder — trigger download
                            try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                        } else if let rv = try? mediaURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                                  rv.ubiquitousItemDownloadingStatus != nil {
                            // System knows about this file in iCloud
                            if rv.ubiquitousItemDownloadingStatus != .current {
                                try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                            }
                        } else {
                            // Truly orphaned — no local file, no iCloud placeholder, no iCloud metadata
                            #if DEBUG
                            print("[MetadataLoader] Media truly missing for: \(id), skipping")
                            #endif
                            continue
                        }

                        item.mediaURL = mediaURL
                        if !item.isVideo {
                            item.thumbnailURL = thumbnailsDir.appendingPathComponent("\(id).jpg")
                        }

                        loadedItems.append(item)

                        // Yield a sorted snapshot every batchSize items
                        if loadedItems.count - lastYieldCount >= batchSize {
                            let sorted = loadedItems.sorted {
                                ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
                            }
                            continuation.yield(LoadUpdate(items: sorted, skippedCount: skipped))
                            lastYieldCount = loadedItems.count
                        }
                    }

                    // Final yield with all items
                    let sorted = loadedItems.sorted {
                        ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
                    }
                    continuation.yield(LoadUpdate(items: sorted, skippedCount: skipped))

                    #if DEBUG
                    if skipped > 0 {
                        print("[MetadataLoader] Skipped \(skipped) metadata files not yet downloaded from iCloud")
                    }
                    print("[MetadataLoader] Loaded \(loadedItems.count) items")
                    #endif

                    continuation.finish()
                } catch {
                    #if DEBUG
                    print("[MetadataLoader] Error: \(error)")
                    #endif
                    continuation.finish(throwing: error)
                }
            }
        }
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
