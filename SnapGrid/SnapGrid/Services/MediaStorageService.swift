import Foundation
import AppKit

final class MediaStorageService: Sendable {

    static let shared = MediaStorageService()

    let baseURL: URL
    let mediaDir: URL       // images/ (named mediaDir to minimize call-site churn)
    let metadataDir: URL
    let thumbnailDir: URL
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
        trashMediaDir = baseURL.appendingPathComponent(".trash/images", isDirectory: true)
        trashMetadataDir = baseURL.appendingPathComponent(".trash/metadata", isDirectory: true)
        trashThumbnailDir = baseURL.appendingPathComponent(".trash/thumbnails", isDirectory: true)

        // Create directories on init
        for dir in [baseURL, mediaDir, metadataDir, thumbnailDir, trashMediaDir, trashMetadataDir, trashThumbnailDir] {
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

        // Track which files we've moved so we can roll back on failure
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
            try moveFile(from: mediaDir.appendingPathComponent(filename),
                         to: trashMediaDir.appendingPathComponent(filename))
            try moveFile(from: metadataDir.appendingPathComponent("\(id).json"),
                         to: trashMetadataDir.appendingPathComponent("\(id).json"))
            try moveFile(from: thumbnailDir.appendingPathComponent("\(id).jpg"),
                         to: trashThumbnailDir.appendingPathComponent("\(id).jpg"))
        } catch {
            rollback()
            throw error
        }
    }

    func restoreFromTrash(filename: String, id: String) throws {
        let fm = FileManager.default

        var movedPairs: [(src: URL, dst: URL)] = []

        func moveFile(from src: URL, to dst: URL) throws {
            guard fm.fileExists(atPath: src.path) else { return }
            try fm.moveItem(at: src, to: dst)
            movedPairs.append((src: src, dst: dst))
        }

        func rollback() {
            for pair in movedPairs.reversed() {
                try? fm.moveItem(at: pair.dst, to: pair.src)
            }
        }

        do {
            try moveFile(from: trashMediaDir.appendingPathComponent(filename),
                         to: mediaDir.appendingPathComponent(filename))
            try moveFile(from: trashMetadataDir.appendingPathComponent("\(id).json"),
                         to: metadataDir.appendingPathComponent("\(id).json"))
            try moveFile(from: trashThumbnailDir.appendingPathComponent("\(id).jpg"),
                         to: thumbnailDir.appendingPathComponent("\(id).jpg"))
        } catch {
            rollback()
            throw error
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
