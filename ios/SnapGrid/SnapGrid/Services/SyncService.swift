import Foundation
import SwiftData

// MARK: - Sidecar JSON Models (matches Mac's MetadataSidecarService)

struct SidecarMetadata: Codable, Sendable {
    let id: String
    let type: String
    let width: Int
    let height: Int
    let createdAt: Date
    let duration: Double?
    let spaceId: String?
    let imageContext: String?
    let imageSummary: String?
    let patterns: [SidecarPattern]?
    let sourceURL: String?
}

struct SidecarPattern: Codable, Sendable {
    let name: String
    let confidence: Double
}

struct SidecarSpace: Codable, Sendable {
    let id: String
    let name: String
    let order: Int
    let createdAt: Date
    let customPrompt: String?
    let useCustomPrompt: Bool
}

/// Wrapper for spaces.json that includes all-space guidance alongside the spaces array.
struct SidecarSpacesFile: Codable, Sendable {
    let spaces: [SidecarSpace]
    let allSpaceGuidance: String?
    let useAllSpaceGuidance: Bool
}

// MARK: - SyncService

/// Reads sidecar JSON files from the iCloud container and syncs them into SwiftData.
/// Read-only — never writes to the filesystem (the Mac app is the writer).
@MainActor
final class SyncService {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Full sync from disk to SwiftData. Call on app launch and when returning to foreground.
    /// Returns the number of iCloud files that were still downloading (skipped).
    @discardableResult
    func sync(rootURL: URL, context: ModelContext) async -> Int {
        let metadataDir = rootURL.appendingPathComponent("metadata")
        let imagesDir = rootURL.appendingPathComponent("images")
        let fm = FileManager.default

        // Phase 1: Import spaces
        syncSpaces(rootURL: rootURL, context: context)

        // Phase 2: Scan metadata files
        guard let contents = try? fm.contentsOfDirectory(
            at: metadataDir,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
            options: []
        ) else {
            print("[SyncService] Cannot read metadata directory")
            return 0
        }

        let jsonFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".json") || name.hasSuffix(".json.icloud")
        }

        print("[SyncService] Found \(jsonFiles.count) metadata files")

        // Phase 3: Load existing items from SwiftData for diffing
        let existingItems = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        var existingById: [String: MediaItem] = [:]
        for item in existingItems {
            existingById[item.id] = item
        }

        var seenIds = Set<String>()
        var skipped = 0
        var imported = 0

        for url in jsonFiles {
            let fileName = url.lastPathComponent

            // iCloud placeholder — trigger download, skip
            if fileName.hasSuffix(".json.icloud") {
                var realName = String(fileName.dropLast(".icloud".count))
                if realName.hasPrefix(".") { realName = String(realName.dropFirst()) }
                let realURL = url.deletingLastPathComponent().appendingPathComponent(realName)
                try? fm.startDownloadingUbiquitousItem(at: realURL)
                skipped += 1
                continue
            }

            // Check if JSON is downloaded
            if let rv = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               let status = rv.ubiquitousItemDownloadingStatus,
               status != .current {
                try? fm.startDownloadingUbiquitousItem(at: url)
                skipped += 1
                continue
            }

            guard let data = try? Data(contentsOf: url) else { continue }
            guard let sidecar = try? Self.decoder.decode(SidecarMetadata.self, from: data) else { continue }

            let id = url.deletingPathExtension().lastPathComponent
            seenIds.insert(id)

            // Check media file exists (locally or as iCloud placeholder)
            let ext = sidecar.type == "video" ? "mp4" : "png"
            let mediaFilename = "\(id).\(ext)"
            let mediaURL = imagesDir.appendingPathComponent(mediaFilename)
            let iCloudPlaceholder = imagesDir.appendingPathComponent(".\(id).\(ext).icloud")

            if !fm.fileExists(atPath: mediaURL.path) {
                if fm.fileExists(atPath: iCloudPlaceholder.path) {
                    try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                } else if let rv = try? mediaURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                          rv.ubiquitousItemDownloadingStatus != nil {
                    if rv.ubiquitousItemDownloadingStatus != .current {
                        try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                    }
                } else {
                    // Truly orphaned — no media file
                    continue
                }
            }

            // Upsert into SwiftData
            if let existing = existingById[id] {
                // Update existing item if analysis changed
                updateIfNeeded(existing, from: sidecar, context: context)
                existingById.removeValue(forKey: id)
            } else {
                // Create new item
                let mediaType: MediaType = sidecar.type == "video" ? .video : .image
                let item = MediaItem(
                    id: id,
                    mediaType: mediaType,
                    filename: mediaFilename,
                    width: sidecar.width,
                    height: sidecar.height,
                    createdAt: sidecar.createdAt,
                    duration: sidecar.duration
                )
                item.sourceURL = sidecar.sourceURL

                // Assign space
                if let spaceId = sidecar.spaceId {
                    let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
                    item.space = try? context.fetch(descriptor).first
                }

                // Assign analysis result
                if let imageContext = sidecar.imageContext, !imageContext.isEmpty {
                    let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                    item.analysisResult = AnalysisResult(
                        imageContext: imageContext,
                        imageSummary: sidecar.imageSummary ?? "",
                        patterns: patterns,
                        provider: "synced",
                        model: "icloud-sync"
                    )
                }

                context.insert(item)
                imported += 1
            }

            // Yield periodically
            if imported % 20 == 0 && imported > 0 {
                context.saveOrLog()
                await Task.yield()
            }
        }

        // Phase 4: Remove orphaned SwiftData items (sidecar was deleted on Mac)
        for (_, orphan) in existingById {
            context.delete(orphan)
        }

        context.saveOrLog()
        print("[SyncService] Sync complete: \(imported) new, \(skipped) pending iCloud, \(existingById.count) removed")
        return skipped
    }

    // MARK: - Spaces

    private func syncSpaces(rootURL: URL, context: ModelContext) {
        let spacesURL = rootURL.appendingPathComponent("spaces.json")
        guard let data = try? Data(contentsOf: spacesURL) else { return }

        // Decode wrapper format first, fall back to legacy bare array
        let sidecars: [SidecarSpace]
        if let file = try? Self.decoder.decode(SidecarSpacesFile.self, from: data) {
            sidecars = file.spaces
            // Sync all-space guidance to UserDefaults so it's available during analysis
            if let allGuidance = file.allSpaceGuidance {
                UserDefaults.standard.set(allGuidance, forKey: "allSpacePrompt")
            }
            UserDefaults.standard.set(file.useAllSpaceGuidance, forKey: "useAllSpacePrompt")
        } else if let legacySpaces = try? Self.decoder.decode([SidecarSpace].self, from: data) {
            sidecars = legacySpaces
        } else {
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        var existingById: [String: Space] = [:]
        for space in existing { existingById[space.id] = space }

        for sidecar in sidecars {
            if let space = existingById[sidecar.id] {
                space.name = sidecar.name
                space.order = sidecar.order
                space.customPrompt = sidecar.customPrompt
                space.useCustomPrompt = sidecar.useCustomPrompt
                existingById.removeValue(forKey: sidecar.id)
            } else {
                let space = Space(
                    id: sidecar.id,
                    name: sidecar.name,
                    order: sidecar.order,
                    createdAt: sidecar.createdAt
                )
                space.customPrompt = sidecar.customPrompt
                space.useCustomPrompt = sidecar.useCustomPrompt
                context.insert(space)
            }
        }

        // Remove spaces that no longer exist in sidecar
        for (_, orphan) in existingById {
            context.delete(orphan)
        }

        context.saveOrLog()
    }

    // MARK: - Update Helpers

    private func updateIfNeeded(_ item: MediaItem, from sidecar: SidecarMetadata, context: ModelContext) {
        // Update space assignment if changed
        if let spaceId = sidecar.spaceId {
            if item.space?.id != spaceId {
                let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
                item.space = try? context.fetch(descriptor).first
            }
        } else if item.space != nil {
            item.space = nil
        }

        // Update source URL if it was added
        if item.sourceURL == nil, let sourceURL = sidecar.sourceURL {
            item.sourceURL = sourceURL
        }

        // Update analysis if it was added/changed
        let hasAnalysis = sidecar.imageContext != nil && !(sidecar.imageContext?.isEmpty ?? true)
        if hasAnalysis && item.analysisResult == nil {
            let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
            item.analysisResult = AnalysisResult(
                imageContext: sidecar.imageContext!,
                imageSummary: sidecar.imageSummary ?? "",
                patterns: patterns,
                provider: "synced",
                model: "icloud-sync"
            )
        }
    }
}
