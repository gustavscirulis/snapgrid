import UIKit
import Foundation

/// Writes images and sidecar JSON directly to the iCloud container.
/// Reuses the same ID and metadata format as the Share Extension.
enum ImageImportService {

    struct ImportResult {
        let successCount: Int
        let failureCount: Int
    }

    /// Import an array of UIImages into the SnapGrid iCloud container.
    /// Writes each image as PNG + sidecar JSON to `rootURL/images/` and `rootURL/metadata/`.
    /// If `spaceId` is provided, the sidecar will reference that space.
    static func importImages(_ images: [UIImage], to rootURL: URL, spaceId: String? = nil) async -> ImportResult {
        let fm = FileManager.default
        let imagesDir = rootURL.appendingPathComponent("images", isDirectory: true)
        let metadataDir = rootURL.appendingPathComponent("metadata", isDirectory: true)

        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var success = 0
        var failure = 0

        for image in images {
            let ok = autoreleasepool { () -> Bool in
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
                let random = String((0..<7).map { _ in chars.randomElement()! })
                let id = "img_\(timestamp)_\(random)"

                guard let pngData = image.pngData() else { return false }

                let width = Int(image.size.width * image.scale)
                let height = Int(image.size.height * image.scale)

                let imageURL = imagesDir.appendingPathComponent("\(id).png")
                let metadataURL = metadataDir.appendingPathComponent("\(id).json")

                do {
                    try pngData.write(to: imageURL, options: .atomic)
                } catch {
                    #if DEBUG
                    print("[ImageImport] Failed to write image \(id): \(error)")
                    #endif
                    return false
                }

                let sidecar = SidecarMetadata(
                    id: id,
                    type: "image",
                    width: width,
                    height: height,
                    createdAt: Date(),
                    duration: nil,
                    spaceId: spaceId,
                    imageContext: nil,
                    imageSummary: nil,
                    patterns: nil,
                    sourceURL: nil
                )

                guard let jsonData = try? encoder.encode(sidecar) else { return false }

                do {
                    try jsonData.write(to: metadataURL, options: .atomic)
                } catch {
                    #if DEBUG
                    print("[ImageImport] Failed to write metadata \(id): \(error)")
                    #endif
                    // Clean up the image file since metadata failed
                    try? fm.removeItem(at: imageURL)
                    return false
                }

                #if DEBUG
                print("[ImageImport] Imported \(id) (\(width)x\(height))")
                #endif
                return true
            }

            if ok {
                success += 1
            } else {
                failure += 1
            }

            // Yield between images to keep UI responsive
            await Task.yield()
        }

        return ImportResult(successCount: success, failureCount: failure)
    }
}
