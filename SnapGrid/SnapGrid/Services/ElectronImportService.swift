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
    private let sidecarService = MetadataSidecarService.shared

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
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // Try standard ~/Documents/SnapGrid first
        let documentsURL = home.appendingPathComponent("Documents/SnapGrid", isDirectory: true)
        if validateLibraryFolder(documentsURL) && countItems(in: documentsURL) > 0 {
            return documentsURL
        }

        // Try iCloud Documents path (when Desktop & Documents is synced to iCloud)
        let iCloudDocsURL = home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents/SnapGrid", isDirectory: true)
        if validateLibraryFolder(iCloudDocsURL) && countItems(in: iCloudDocsURL) > 0 {
            return iCloudDocsURL
        }

        // Return whichever exists even with 0 items (user can still proceed)
        if validateLibraryFolder(documentsURL) { return documentsURL }
        if validateLibraryFolder(iCloudDocsURL) { return iCloudDocsURL }
        return nil
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
        return files.filter { isJSONOrPlaceholder($0) }.count
    }

    /// Check if a URL is a .json file or an iCloud placeholder for a .json file (.abc.json.icloud)
    private func isJSONOrPlaceholder(_ url: URL) -> Bool {
        if url.pathExtension == "json" { return true }
        // iCloud placeholders: .filename.json.icloud
        let name = url.lastPathComponent
        return name.hasPrefix(".") && name.hasSuffix(".json.icloud")
    }

    /// Resolve the actual file URL, downloading iCloud placeholders if needed.
    /// Returns the downloaded URL when ready, or nil if download fails.
    private func resolveICloudFile(at url: URL) async -> URL? {
        let fm = FileManager.default

        // Already a real file
        if fm.fileExists(atPath: url.path) && url.pathExtension != "icloud" {
            return url
        }

        // Check for iCloud placeholder version
        let dir = url.deletingLastPathComponent()
        let placeholderName = ".\(url.lastPathComponent).icloud"
        let placeholderURL = dir.appendingPathComponent(placeholderName)

        let targetURL: URL
        if fm.fileExists(atPath: placeholderURL.path) {
            targetURL = placeholderURL
        } else if url.pathExtension == "icloud" {
            targetURL = url
        } else if fm.fileExists(atPath: url.path) {
            return url
        } else {
            return nil
        }

        // Trigger download
        do {
            try fm.startDownloadingUbiquitousItem(at: targetURL)
        } catch {
            return nil
        }

        // Wait for download (up to 30 seconds)
        let realName = targetURL.lastPathComponent
            .replacingOccurrences(of: ".icloud", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let realURL = dir.appendingPathComponent(realName)

        for _ in 0..<60 {
            if fm.fileExists(atPath: realURL.path) { return realURL }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
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

        // 1. Enumerate metadata files (including iCloud placeholders)
        let metadataDir = electronRoot.appendingPathComponent("metadata")
        let allFiles = ((try? FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { isJSONOrPlaceholder($0) }
        totalItems = allFiles.count

        // 2. Build duplicate skip-set from existing sourceIds
        let existingSourceIds = fetchExistingSourceIds(context: context)

        // 3. Import spaces
        let (spaceMap, newSpaceCount) = await importSpaces(from: electronRoot, into: context)
        spacesImported = newSpaceCount
        try? context.save()

        // 4. Process each metadata file — save after each item for safe incremental import
        for fileURL in allFiles {
            if isCancelled { break }

            // Extract electronId: handle both "abc.json" and ".abc.json.icloud" placeholders
            let electronId = Self.extractId(from: fileURL)
            currentFilename = electronId

            // Skip duplicates
            if existingSourceIds.contains(electronId) {
                duplicatesSkipped += 1
                importedCount += 1
                await Task.yield()
                continue
            }

            // Resolve iCloud placeholder to real file if needed
            var resolvedURL = await resolveICloudFile(at: fileURL)
            if resolvedURL == nil {
                let jsonURL = fileURL.deletingLastPathComponent().appendingPathComponent("\(electronId).json")
                resolvedURL = await resolveICloudFile(at: jsonURL)
            }
            guard let resolvedURL else {
                print("[ElectronImport] Could not download \(electronId) from iCloud")
                errors += 1
                importedCount += 1
                await Task.yield()
                continue
            }

            do {
                try await importSingleItem(
                    metadataURL: resolvedURL,
                    electronId: electronId,
                    electronRoot: electronRoot,
                    spaceMap: spaceMap,
                    context: context
                )
                try? context.save()

                // Write JSON sidecar so item syncs to other devices via iCloud
                let itemDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { $0.sourceId == electronId })
                if let imported = try? context.fetch(itemDescriptor).last {
                    sidecarService.writeSidecar(for: imported)
                }
            } catch {
                print("[ElectronImport] Error importing \(electronId): \(error)")
                errors += 1
            }

            importedCount += 1

            // Yield to let SwiftUI update progress and process user events (e.g. Cancel)
            await Task.yield()
        }

        // Write spaces.json so spaces sync to other devices
        if let allSpaces = try? context.fetch(FetchDescriptor<Space>()) {
            sidecarService.writeSpaces(allSpaces)
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

    private func importSpaces(from electronRoot: URL, into context: ModelContext) async -> (map: [String: Space], created: Int) {
        let spacesURL = electronRoot.appendingPathComponent("spaces.json")
        let resolvedURL = await resolveICloudFile(at: spacesURL) ?? spacesURL
        guard let data = try? Data(contentsOf: resolvedURL),
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
        // Parse metadata first (file already resolved by caller)
        let data = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(ElectronMetadata.self, from: data)

        // Resolve media file (may need iCloud download)
        let isVideo = metadata.type == "video" || electronId.hasPrefix("vid_")
        let imagesDir = electronRoot.appendingPathComponent("images")
        let extensions = isVideo ? ["mp4", "mov"] : ["png", "jpg"]
        var sourceURL: URL?
        for ext in extensions {
            let candidate = imagesDir.appendingPathComponent("\(electronId).\(ext)")
            if let resolved = await resolveICloudFile(at: candidate) {
                sourceURL = resolved
                break
            }
        }
        guard let sourceURL else { throw ImportError.mediaFileMissing(electronId) }

        // Resolve thumbnail
        let thumbSource = electronRoot.appendingPathComponent("thumbnails/\(electronId).jpg")
        let resolvedThumb = await resolveICloudFile(at: thumbSource)

        // Perform heavy file I/O on a background thread
        let newId = UUID().uuidString
        let targetExt = isVideo ? "mp4" : "png"
        let filename = "\(newId).\(targetExt)"

        try await Task.detached { [storage] in
            _ = try storage.copyMedia(from: sourceURL, filename: filename)

            // Handle thumbnail
            if let resolvedThumb, let thumbData = try? Data(contentsOf: resolvedThumb) {
                _ = try? storage.saveThumbnail(data: thumbData, id: newId)
            } else if isVideo {
                if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: storage.mediaURL(filename: filename)) {
                    _ = try? ThumbnailService.generateThumbnail(from: posterFrame, id: newId)
                }
            } else {
                _ = try? await ThumbnailService.generateThumbnail(from: storage.mediaURL(filename: filename), id: newId)
            }
        }.value

        // For videos, use poster frame dimensions as authoritative (handles PAR, rotation)
        var width = metadata.width ?? 0
        var height = metadata.height ?? 0
        if isVideo, width > 0, height > 0 {
            if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: storage.mediaURL(filename: filename)),
               let pixelSize = posterFrame.pixelSize,
               Int(pixelSize.width) > 0, Int(pixelSize.height) > 0 {
                width = Int(pixelSize.width)
                height = Int(pixelSize.height)
            }
        }

        // Create and insert model objects on main actor
        let item = MediaItem(
            id: newId,
            mediaType: isVideo ? .video : .image,
            filename: filename,
            width: width,
            height: height,
            createdAt: Self.parseDate(metadata.createdAt),
            duration: metadata.duration
        )
        item.sourceId = electronId

        if let spaceId = metadata.spaceId, let space = spaceMap[spaceId] {
            item.space = space
        }

        if let imageContext = metadata.imageContext, !imageContext.isEmpty {
            var imageSummary = ""
            if let s = metadata.patterns?.first?.imageSummary { imageSummary = s }
            else if let s = metadata.title { imageSummary = s }
            else if let s = metadata.patterns?.first?.name { imageSummary = s }

            let electronPatterns = metadata.patterns ?? []
            let patterns = electronPatterns.map {
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

    /// Extract the base ID from a filename like "abc.json" or ".abc.json.icloud"
    private static func extractId(from url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasPrefix(".") && name.hasSuffix(".json.icloud") {
            // ".abc123.json.icloud" → "abc123"
            let trimmed = String(name.dropFirst()) // remove leading "."
            return String(trimmed.dropLast(".json.icloud".count))
        }
        return url.deletingPathExtension().lastPathComponent
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
