import Foundation

struct LoadResult {
    let items: [SnapGridItem]
    let skippedCount: Int
}

class MetadataLoader {
    private let fileSystem: FileSystemManager

    init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }

    func loadAllItems() async throws -> LoadResult {
        guard let metadataDir = fileSystem.metadataDir,
              let imagesDir = fileSystem.imagesDir,
              let thumbnailsDir = fileSystem.thumbnailsDir else {
            throw LoaderError.noAccess
        }

        // Move all file I/O off the main thread
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fm = FileManager.default

                    let contents = try fm.contentsOfDirectory(
                        at: metadataDir,
                        includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
                        options: [.skipsHiddenFiles]
                    )

                    let jsonFiles = contents.filter { $0.pathExtension == "json" }
                    print("[MetadataLoader] Found \(jsonFiles.count) metadata files")

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
                            print("[MetadataLoader] Could not read: \(url.lastPathComponent)")
                            continue
                        }

                        guard var item = try? decoder.decode(SnapGridItem.self, from: data) else {
                            print("[MetadataLoader] Could not decode: \(url.lastPathComponent)")
                            continue
                        }

                        let id = url.deletingPathExtension().lastPathComponent
                        let ext = item.isVideo ? "mp4" : "png"
                        let mediaURL = imagesDir.appendingPathComponent("\(id).\(ext)")

                        // Skip orphaned metadata (JSON exists but media file doesn't)
                        if !fm.fileExists(atPath: mediaURL.path) {
                            print("[MetadataLoader] Media file missing for: \(id), skipping")
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

                    if skipped > 0 {
                        print("[MetadataLoader] Skipped \(skipped) files not yet downloaded from iCloud")
                    }
                    print("[MetadataLoader] Loaded \(loadedItems.count) items")

                    let sorted = loadedItems.sorted {
                        ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
                    }

                    continuation.resume(returning: LoadResult(items: sorted, skippedCount: skipped))
                } catch {
                    print("[MetadataLoader] Error: \(error)")
                    continuation.resume(throwing: error)
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
