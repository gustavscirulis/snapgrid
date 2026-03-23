import Foundation
import AppKit

final class MediaStorageService: Sendable {

    static let shared = MediaStorageService()

    let baseURL: URL
    let mediaDir: URL       // images/ (named mediaDir to minimize call-site churn)
    let metadataDir: URL
    let thumbnailDir: URL
    let queueDir: URL
    let trashMediaDir: URL
    let trashMetadataDir: URL
    let trashThumbnailDir: URL
    let isUsingiCloud: Bool

    private init() {
        // Try to resolve the iCloud container; fall back to Application Support
        let fm = FileManager.default
        if let containerURL = fm.url(forUbiquityContainerIdentifier: "iCloud.com.SnapGrid") {
            let docsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            baseURL = docsURL
            isUsingiCloud = true
        } else {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            baseURL = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
            isUsingiCloud = false
        }

        mediaDir = baseURL.appendingPathComponent("images", isDirectory: true)
        metadataDir = baseURL.appendingPathComponent("metadata", isDirectory: true)
        thumbnailDir = baseURL.appendingPathComponent("thumbnails", isDirectory: true)
        queueDir = baseURL.appendingPathComponent("queue", isDirectory: true)
        trashMediaDir = baseURL.appendingPathComponent(".trash/images", isDirectory: true)
        trashMetadataDir = baseURL.appendingPathComponent(".trash/metadata", isDirectory: true)
        trashThumbnailDir = baseURL.appendingPathComponent(".trash/thumbnails", isDirectory: true)

        // Create directories on init
        for dir in [baseURL, mediaDir, metadataDir, thumbnailDir, queueDir, trashMediaDir, trashMetadataDir, trashThumbnailDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func saveMedia(data: Data, filename: String) throws -> URL {
        let url = mediaDir.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    func copyMedia(from sourceURL: URL, filename: String) throws -> URL {
        let destURL = mediaDir.appendingPathComponent(filename)
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    func saveThumbnail(data: Data, id: String) throws -> URL {
        let url = thumbnailDir.appendingPathComponent("\(id).jpg")
        try data.write(to: url)
        return url
    }

    func mediaURL(filename: String) -> URL {
        mediaDir.appendingPathComponent(filename)
    }

    func thumbnailURL(id: String) -> URL {
        thumbnailDir.appendingPathComponent("\(id).jpg")
    }

    func deleteMedia(filename: String) throws {
        let url = mediaDir.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: url)
    }

    func deleteThumbnail(id: String) throws {
        let url = thumbnailDir.appendingPathComponent("\(id).jpg")
        try FileManager.default.removeItem(at: url)
    }

    func mediaExists(filename: String) -> Bool {
        FileManager.default.fileExists(atPath: mediaDir.appendingPathComponent(filename).path)
    }

    func thumbnailExists(id: String) -> Bool {
        FileManager.default.fileExists(atPath: thumbnailDir.appendingPathComponent("\(id).jpg").path)
    }

    // MARK: - Trash

    func moveToTrash(filename: String, id: String) throws {
        let fm = FileManager.default

        // Move media file
        let mediaSrc = mediaDir.appendingPathComponent(filename)
        let mediaDst = trashMediaDir.appendingPathComponent(filename)
        if fm.fileExists(atPath: mediaSrc.path) {
            if fm.fileExists(atPath: mediaDst.path) { try fm.removeItem(at: mediaDst) }
            try fm.moveItem(at: mediaSrc, to: mediaDst)
        }

        // Move metadata sidecar
        let metaSrc = metadataDir.appendingPathComponent("\(id).json")
        let metaDst = trashMetadataDir.appendingPathComponent("\(id).json")
        if fm.fileExists(atPath: metaSrc.path) {
            if fm.fileExists(atPath: metaDst.path) { try fm.removeItem(at: metaDst) }
            try fm.moveItem(at: metaSrc, to: metaDst)
        }

        // Move thumbnail
        let thumbSrc = thumbnailDir.appendingPathComponent("\(id).jpg")
        let thumbDst = trashThumbnailDir.appendingPathComponent("\(id).jpg")
        if fm.fileExists(atPath: thumbSrc.path) {
            if fm.fileExists(atPath: thumbDst.path) { try fm.removeItem(at: thumbDst) }
            try fm.moveItem(at: thumbSrc, to: thumbDst)
        }
    }

    func restoreFromTrash(filename: String, id: String) throws {
        let fm = FileManager.default

        let mediaSrc = trashMediaDir.appendingPathComponent(filename)
        let mediaDst = mediaDir.appendingPathComponent(filename)
        if fm.fileExists(atPath: mediaSrc.path) {
            try fm.moveItem(at: mediaSrc, to: mediaDst)
        }

        let metaSrc = trashMetadataDir.appendingPathComponent("\(id).json")
        let metaDst = metadataDir.appendingPathComponent("\(id).json")
        if fm.fileExists(atPath: metaSrc.path) {
            try fm.moveItem(at: metaSrc, to: metaDst)
        }

        let thumbSrc = trashThumbnailDir.appendingPathComponent("\(id).jpg")
        let thumbDst = thumbnailDir.appendingPathComponent("\(id).jpg")
        if fm.fileExists(atPath: thumbSrc.path) {
            try fm.moveItem(at: thumbSrc, to: thumbDst)
        }
    }

    func emptyTrash() {
        let fm = FileManager.default
        for dir in [trashMediaDir, trashMetadataDir, trashThumbnailDir] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    func emptyOldTrash(olderThan interval: TimeInterval = 30 * 24 * 3600) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-interval)

        for dir in [trashMediaDir, trashMetadataDir, trashThumbnailDir] {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files {
                guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                      let modified = attrs[.modificationDate] as? Date,
                      modified < cutoff else { continue }
                try? fm.removeItem(at: file)
            }
        }
    }
}
