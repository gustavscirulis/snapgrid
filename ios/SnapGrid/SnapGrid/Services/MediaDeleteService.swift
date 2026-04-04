import Foundation

/// Moves media files to the `.trash/` directory, matching the Mac app's
/// `MediaStorageService.moveToTrash` convention and shared trash structure.
enum MediaDeleteService {

    /// Move a media item's files (image/video, metadata sidecar, thumbnail) to `.trash/`.
    /// Uses a rollback pattern: if any move fails, previously moved files are restored.
    static func moveToTrash(filename: String, id: String, rootURL: URL) throws {
        let fm = FileManager.default

        let imagesDir = rootURL.appendingPathComponent("images")
        let metadataDir = rootURL.appendingPathComponent("metadata")
        let thumbnailsDir = rootURL.appendingPathComponent("thumbnails")

        let trashImagesDir = rootURL.appendingPathComponent(".trash/images")
        let trashMetadataDir = rootURL.appendingPathComponent(".trash/metadata")
        let trashThumbnailsDir = rootURL.appendingPathComponent(".trash/thumbnails")

        // Ensure trash directories exist
        for dir in [trashImagesDir, trashMetadataDir, trashThumbnailsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Track moved files for rollback on failure
        var movedPairs: [(src: URL, dst: URL)] = []

        func moveFile(from src: URL, to dst: URL) throws {
            guard fm.fileExists(atPath: src.path) else { return }
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.moveItem(at: src, to: dst)
            movedPairs.append((src: src, dst: dst))
        }

        func rollback() {
            for pair in movedPairs.reversed() {
                try? fm.moveItem(at: pair.dst, to: pair.src)
            }
        }

        do {
            try moveFile(from: imagesDir.appendingPathComponent(filename),
                         to: trashImagesDir.appendingPathComponent(filename))
            try moveFile(from: metadataDir.appendingPathComponent("\(id).json"),
                         to: trashMetadataDir.appendingPathComponent("\(id).json"))
            try moveFile(from: thumbnailsDir.appendingPathComponent("\(id).jpg"),
                         to: trashThumbnailsDir.appendingPathComponent("\(id).jpg"))
        } catch {
            rollback()
            throw error
        }
    }

    /// Delete trash files older than the given interval (default 30 days).
    /// Matches the Mac app's `MediaStorageService.emptyOldTrash` behavior.
    static func emptyOldTrash(rootURL: URL, olderThan interval: TimeInterval = 30 * 24 * 3600) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-interval)

        let trashDirs = [
            rootURL.appendingPathComponent(".trash/images"),
            rootURL.appendingPathComponent(".trash/metadata"),
            rootURL.appendingPathComponent(".trash/thumbnails")
        ]

        for dir in trashDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files {
                guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                      let modified = attrs[.modificationDate] as? Date,
                      modified < cutoff else { continue }
                try? fm.removeItem(at: file)
            }
        }
    }
}
