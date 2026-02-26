import Foundation
import AppKit

@Observable
final class MediaStorageService: Sendable {

    static let shared = MediaStorageService()

    let baseURL: URL
    let mediaDir: URL
    let thumbnailDir: URL
    let queueDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        mediaDir = baseURL.appendingPathComponent("media", isDirectory: true)
        thumbnailDir = baseURL.appendingPathComponent("thumbnails", isDirectory: true)
        queueDir = baseURL.appendingPathComponent("queue", isDirectory: true)

        // Create directories on init
        let fm = FileManager.default
        for dir in [baseURL, mediaDir, thumbnailDir, queueDir] {
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
}
