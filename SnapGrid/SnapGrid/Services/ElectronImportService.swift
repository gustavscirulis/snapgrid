import Foundation
import SwiftData
import AppKit

// MARK: - Electron JSON Models

private struct ElectronMetadata: Codable, Sendable {
    let type: String?
    let width: Int?
    let height: Int?
    let createdAt: String?
    let title: String?
    let description: String?
    let imageContext: String?
    let patterns: [ElectronPattern]?
    let spaceId: String?
    let duration: Double?
}

private struct ElectronPattern: Codable, Sendable {
    let name: String
    let confidence: Double
    let imageContext: String?
    let imageSummary: String?
}

private struct ElectronSpace: Codable {
    let id: String
    let name: String
    let order: Int
    let createdAt: String?
    let customPrompt: String?
    let useCustomPrompt: Bool?
}

// MARK: - Import Result

struct ElectronImportResult {
    let itemsImported: Int
    let spacesImported: Int
    let duplicatesSkipped: Int
    let errors: Int
}

// MARK: - Service

@Observable
@MainActor
final class ElectronImportService {

    var isImporting = false
    var totalItems = 0
    var importedCount = 0
    var currentFilename = ""
    var isCancelled = false
    var importResult: ElectronImportResult?

    private let storage = MediaStorageService.shared

    // ISO 8601 date parsing (matches iOS app pattern)
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterBasic = ISO8601DateFormatter()

    private static func parseDate(_ string: String?) -> Date {
        guard let string else { return .now }
        return isoFormatterFractional.date(from: string)
            ?? isoFormatterBasic.date(from: string)
            ?? .now
    }

    // MARK: - Detection

    func detectElectronLibrary() -> URL? {
        let documentsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/SnapGrid", isDirectory: true)
        guard validateLibraryFolder(documentsURL) else { return nil }
        return documentsURL
    }

    func validateLibraryFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let imagesExists = fm.fileExists(atPath: url.appendingPathComponent("images").path, isDirectory: &isDir) && isDir.boolValue
        let metadataExists = fm.fileExists(atPath: url.appendingPathComponent("metadata").path, isDirectory: &isDir) && isDir.boolValue
        return imagesExists && metadataExists
    }

    func countItems(in electronRoot: URL) -> Int {
        let metadataDir = electronRoot.appendingPathComponent("metadata")
        let files = (try? FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.count
    }

    // MARK: - Import

    func importLibrary(from electronRoot: URL, into context: ModelContext) async {
        isImporting = true
        isCancelled = false
        importedCount = 0
        importResult = nil

        var spacesImported = 0
        var duplicatesSkipped = 0
        var errors = 0

        // 1. Enumerate metadata files
        let metadataDir = electronRoot.appendingPathComponent("metadata")
        let allFiles = ((try? FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        totalItems = allFiles.count

        // 2. Build duplicate skip-set from existing sourceIds
        let existingSourceIds = fetchExistingSourceIds(context: context)

        // 3. Import spaces
        let (spaceMap, newSpaceCount) = importSpaces(from: electronRoot, into: context)
        spacesImported = newSpaceCount
        try? context.save()

        // 4. Process each metadata file — save after each item for safe incremental import
        for fileURL in allFiles {
            if isCancelled { break }

            let electronId = fileURL.deletingPathExtension().lastPathComponent
            currentFilename = electronId

            // Skip duplicates
            if existingSourceIds.contains(electronId) {
                duplicatesSkipped += 1
                importedCount += 1
                await Task.yield()
                continue
            }

            do {
                try await importSingleItem(
                    metadataURL: fileURL,
                    electronId: electronId,
                    electronRoot: electronRoot,
                    spaceMap: spaceMap,
                    context: context
                )
                // Save immediately — each item is complete with its AnalysisResult,
                // so the database is always in a consistent state
                try? context.save()
            } catch {
                print("[ElectronImport] Error importing \(electronId): \(error)")
                errors += 1
            }

            importedCount += 1

            // Yield to let SwiftUI update progress and process user events (e.g. Cancel)
            await Task.yield()
        }

        currentFilename = ""
        isImporting = false
        importResult = ElectronImportResult(
            itemsImported: importedCount - duplicatesSkipped - errors,
            spacesImported: spacesImported,
            duplicatesSkipped: duplicatesSkipped,
            errors: errors
        )
    }

    func cancel() {
        isCancelled = true
    }

    // MARK: - Private

    private func importSpaces(from electronRoot: URL, into context: ModelContext) -> (map: [String: Space], created: Int) {
        let spacesURL = electronRoot.appendingPathComponent("spaces.json")
        guard let data = try? Data(contentsOf: spacesURL),
              let electronSpaces = try? JSONDecoder().decode([ElectronSpace].self, from: data) else {
            return ([:], 0)
        }

        // Check for already-imported spaces by name to avoid duplicates on re-import
        let existingDescriptor = FetchDescriptor<Space>()
        let existingSpaces = (try? context.fetch(existingDescriptor)) ?? []

        var map: [String: Space] = [:]
        var created = 0
        for electronSpace in electronSpaces {
            // If a space with the same name already exists, reuse it
            if let existing = existingSpaces.first(where: { $0.name == electronSpace.name }) {
                map[electronSpace.id] = existing
                continue
            }

            let space = Space(
                name: electronSpace.name,
                order: electronSpace.order,
                createdAt: Self.parseDate(electronSpace.createdAt)
            )
            space.customPrompt = electronSpace.customPrompt
            space.useCustomPrompt = electronSpace.useCustomPrompt ?? false
            context.insert(space)
            map[electronSpace.id] = space
            created += 1
        }

        return (map, created)
    }

    private func fetchExistingSourceIds(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        return Set(items.compactMap(\.sourceId))
    }

    /// Import a single item and return its filename (for cleanup tracking).
    @discardableResult
    private func importSingleItem(
        metadataURL: URL,
        electronId: String,
        electronRoot: URL,
        spaceMap: [String: Space],
        context: ModelContext
    ) async throws -> String {
        // Perform heavy file I/O on a background thread
        let result = try await Task.detached { [storage] in
            let data = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(ElectronMetadata.self, from: data)

            // Determine media type
            let isVideo = metadata.type == "video" || electronId.hasPrefix("vid_")
            let expectedExt = isVideo ? "mp4" : "png"
            let imagesDir = electronRoot.appendingPathComponent("images")
            var sourceURL = imagesDir.appendingPathComponent("\(electronId).\(expectedExt)")

            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                let altExt = isVideo ? "mov" : "jpg"
                sourceURL = imagesDir.appendingPathComponent("\(electronId).\(altExt)")
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    throw ImportError.mediaFileMissing(electronId)
                }
            }

            // Generate new ID and copy media
            let newId = UUID().uuidString
            let targetExt = isVideo ? "mp4" : "png"
            let filename = "\(newId).\(targetExt)"
            _ = try storage.copyMedia(from: sourceURL, filename: filename)

            // Handle thumbnail
            let thumbSource = electronRoot.appendingPathComponent("thumbnails/\(electronId).jpg")
            if FileManager.default.fileExists(atPath: thumbSource.path),
               let thumbData = try? Data(contentsOf: thumbSource) {
                _ = try? storage.saveThumbnail(data: thumbData, id: newId)
            } else if isVideo {
                if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: storage.mediaURL(filename: filename)) {
                    _ = try? ThumbnailService.generateThumbnail(from: posterFrame, id: newId)
                }
            } else {
                _ = try? await ThumbnailService.generateThumbnail(from: storage.mediaURL(filename: filename), id: newId)
            }

            return (metadata, isVideo, newId, filename)
        }.value

        let (metadata, isVideo, newId, filename) = result

        // Create and insert model objects on main actor
        let item = MediaItem(
            id: newId,
            mediaType: isVideo ? .video : .image,
            filename: filename,
            width: metadata.width ?? 0,
            height: metadata.height ?? 0,
            createdAt: Self.parseDate(metadata.createdAt),
            duration: metadata.duration
        )
        item.sourceId = electronId

        if let spaceId = metadata.spaceId, let space = spaceMap[spaceId] {
            item.space = space
        }

        if let imageContext = metadata.imageContext, !imageContext.isEmpty {
            let imageSummary = metadata.patterns?.first?.imageSummary
                ?? metadata.title
                ?? metadata.patterns?.first?.name
                ?? ""

            let patterns = (metadata.patterns ?? []).map {
                PatternTag(name: $0.name, confidence: $0.confidence)
            }

            let result = AnalysisResult(
                imageContext: imageContext,
                imageSummary: imageSummary,
                patterns: patterns,
                analyzedAt: Self.parseDate(metadata.createdAt),
                provider: "imported",
                model: "electron-import"
            )
            item.analysisResult = result
        }

        context.insert(item)
        return filename
    }

    enum ImportError: LocalizedError {
        case mediaFileMissing(String)

        var errorDescription: String? {
            switch self {
            case .mediaFileMissing(let id): return "Media file not found for \(id)"
            }
        }
    }
}
