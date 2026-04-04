import Foundation
import UniformTypeIdentifiers

enum SupportedMedia {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
    static let videoExtensions: Set<String> = ["mp4", "webm", "mov", "avi", "m4v"]
    static let allExtensions: Set<String> = imageExtensions.union(videoExtensions)

    static func isImage(_ ext: String) -> Bool { imageExtensions.contains(ext.lowercased()) }
    static func isVideo(_ ext: String) -> Bool { videoExtensions.contains(ext.lowercased()) }
    static func isSupported(_ ext: String) -> Bool { allExtensions.contains(ext.lowercased()) }

    /// UTTypes for the import file picker. Note: .webm has no system UTType.
    static let importableContentTypes: [UTType] = [
        .png, .jpeg, .gif, .bmp, .tiff, .webP, .heic,
        .mpeg4Movie, .movie, .avi
    ]

    /// Maps MIME types to file extensions for URL downloads.
    static let mimeToExtension: [String: String] = [
        "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg",
        "image/gif": "gif", "image/webp": "webp", "image/bmp": "bmp",
        "image/tiff": "tiff", "image/heic": "heic",
        "video/mp4": "mp4", "video/webm": "webm",
        "video/quicktime": "mov", "video/x-msvideo": "avi", "video/x-m4v": "m4v",
    ]
}
