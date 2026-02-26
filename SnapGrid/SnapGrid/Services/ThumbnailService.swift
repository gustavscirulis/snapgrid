import AppKit
import Foundation

enum ThumbnailService {

    static func generateThumbnail(from sourceURL: URL, id: String, storage: MediaStorageService = .shared) async throws -> URL {
        let data = try await Task.detached(priority: .utility) {
            guard let image = NSImage(contentsOf: sourceURL) else {
                throw ThumbnailError.cannotLoadImage
            }
            guard let jpegData = image.thumbnailData(maxWidth: 800, quality: 0.9) else {
                throw ThumbnailError.cannotGenerateThumbnail
            }
            return jpegData
        }.value

        return try storage.saveThumbnail(data: data, id: id)
    }

    static func generateThumbnail(from image: NSImage, id: String, storage: MediaStorageService = .shared) throws -> URL {
        guard let jpegData = image.thumbnailData(maxWidth: 800, quality: 0.9) else {
            throw ThumbnailError.cannotGenerateThumbnail
        }
        return try storage.saveThumbnail(data: jpegData, id: id)
    }

    enum ThumbnailError: LocalizedError {
        case cannotLoadImage
        case cannotGenerateThumbnail

        var errorDescription: String? {
            switch self {
            case .cannotLoadImage: return "Cannot load image file"
            case .cannotGenerateThumbnail: return "Cannot generate thumbnail"
            }
        }
    }
}
