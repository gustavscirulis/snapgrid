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
    let spaceIds: [String]?
    let imageContext: String?
    let imageSummary: String?
    let patterns: [SidecarPattern]?
    let sourceURL: String?
    let analyzedAt: Date?

    init(
        id: String,
        type: String,
        width: Int,
        height: Int,
        createdAt: Date,
        duration: Double?,
        spaceIds: [String]? = nil,
        spaceId: String? = nil,
        imageContext: String?,
        imageSummary: String?,
        patterns: [SidecarPattern]?,
        sourceURL: String?,
        analyzedAt: Date?
    ) {
        self.id = id
        self.type = type
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.duration = duration
        if let spaceIds, !spaceIds.isEmpty {
            self.spaceIds = spaceIds
        } else if let spaceId {
            self.spaceIds = [spaceId]
        } else {
            self.spaceIds = nil
        }
        self.imageContext = imageContext
        self.imageSummary = imageSummary
        self.patterns = patterns
        self.sourceURL = sourceURL
        self.analyzedAt = analyzedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case width
        case height
        case createdAt
        case duration
        case spaceIds
        case spaceId
        case imageContext
        case imageSummary
        case patterns
        case sourceURL
        case analyzedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        if let decodedSpaceIds = try container.decodeIfPresent([String].self, forKey: .spaceIds),
           !decodedSpaceIds.isEmpty {
            spaceIds = decodedSpaceIds
        } else if let legacySpaceId = try container.decodeIfPresent(String.self, forKey: .spaceId) {
            spaceIds = [legacySpaceId]
        } else {
            spaceIds = nil
        }
        imageContext = try container.decodeIfPresent(String.self, forKey: .imageContext)
        imageSummary = try container.decodeIfPresent(String.self, forKey: .imageSummary)
        patterns = try container.decodeIfPresent([SidecarPattern].self, forKey: .patterns)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        analyzedAt = try container.decodeIfPresent(Date.self, forKey: .analyzedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(spaceIds, forKey: .spaceIds)
        try container.encodeIfPresent(imageContext, forKey: .imageContext)
        try container.encodeIfPresent(imageSummary, forKey: .imageSummary)
        try container.encodeIfPresent(patterns, forKey: .patterns)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(analyzedAt, forKey: .analyzedAt)
    }

    var normalizedSpaceIDs: [String] {
        spaceIds ?? []
    }

    var spaceId: String? {
        normalizedSpaceIDs.first
    }
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

        let isUsingiCloud = FileSystemManager.shared?.isUsingiCloud ?? false

        let jsonFiles = contents.filter { url in
            let name = url.lastPathComponent
            if isUsingiCloud {
                return name.hasSuffix(".json") || name.hasSuffix(".json.icloud")
            }
            return name.hasSuffix(".json")
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
            if isUsingiCloud && fileName.hasSuffix(".json.icloud") {
                var realName = String(fileName.dropLast(".icloud".count))
                if realName.hasPrefix(".") { realName = String(realName.dropFirst()) }
                let realURL = url.deletingLastPathComponent().appendingPathComponent(realName)
                try? fm.startDownloadingUbiquitousItem(at: realURL)
                skipped += 1
                continue
            }

            // Check if JSON is downloaded (iCloud only)
            if isUsingiCloud,
               let rv = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
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
                if isUsingiCloud {
                    // iCloud: check for placeholder and trigger download
                    if fm.fileExists(atPath: iCloudPlaceholder.path) {
                        try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                    } else if let rv = try? mediaURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                              rv.ubiquitousItemDownloadingStatus != nil {
                        if rv.ubiquitousItemDownloadingStatus != .current {
                            try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                        }
                    } else {
                        continue // Orphaned sidecar
                    }
                } else {
                    // Local mode: no media file means orphaned sidecar
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
                let resolvedSpaces = spaces(for: sidecar.normalizedSpaceIDs, in: context)
                item.setMembership(resolvedSpaces)

                // Assign analysis result
                if let imageContext = sidecar.imageContext, !imageContext.isEmpty {
                    let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                    item.analysisResult = AnalysisResult(
                        imageContext: imageContext,
                        imageSummary: sidecar.imageSummary ?? "",
                        patterns: patterns,
                        analyzedAt: sidecar.analyzedAt ?? .now,
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
        let resolvedSpaces = spaces(for: sidecar.normalizedSpaceIDs, in: context)
        if item.orderedSpaceIDs != resolvedSpaces.map(\.id) {
            item.setMembership(resolvedSpaces)
        }

        // Update source URL if it was added
        if item.sourceURL == nil, let sourceURL = sidecar.sourceURL {
            item.sourceURL = sourceURL
        }

        // Update analysis if the remote sidecar has newer or missing-locally analysis
        let hasAnalysis = sidecar.imageContext != nil && !(sidecar.imageContext?.isEmpty ?? true)
        if hasAnalysis {
            let shouldSync: Bool
            if item.analysisResult == nil {
                shouldSync = true
            } else if let remoteDate = sidecar.analyzedAt,
                      let localDate = item.analysisResult?.analyzedAt,
                      remoteDate > localDate {
                shouldSync = true
            } else {
                shouldSync = false
            }

            if shouldSync {
                let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                item.analysisResult = AnalysisResult(
                    imageContext: sidecar.imageContext!,
                    imageSummary: sidecar.imageSummary ?? "",
                    patterns: patterns,
                    analyzedAt: sidecar.analyzedAt ?? .now,
                    provider: "synced",
                    model: "icloud-sync"
                )
            }
        }
    }

    private func spaces(for ids: [String], in context: ModelContext) -> [Space] {
        guard !ids.isEmpty else { return [] }
        let availableSpaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        let idSet = Set(ids)
        return availableSpaces
            .filter { idSet.contains($0.id) }
            .membershipSorted()
    }
}
