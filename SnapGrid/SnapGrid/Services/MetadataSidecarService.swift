import Foundation
import SwiftData

// MARK: - Sidecar JSON Models

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
    let analyzedAt: Date?
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

// MARK: - Service

final class MetadataSidecarService: Sendable {

    static let shared = MetadataSidecarService()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    let storage: MediaStorageService

    private convenience init() {
        self.init(storage: .shared)
    }

    init(storage: MediaStorageService) {
        self.storage = storage
    }

    // MARK: - Item Sidecars

    func writeSidecar(for item: MediaItem) {
        let storage = self.storage
        let sidecar = SidecarMetadata(
            id: item.id,
            type: item.mediaType.rawValue,
            width: item.width,
            height: item.height,
            createdAt: item.createdAt,
            duration: item.duration,
            spaceId: item.space?.id,
            imageContext: item.analysisResult?.imageContext,
            imageSummary: item.analysisResult?.imageSummary,
            patterns: item.analysisResult?.patterns.map { SidecarPattern(name: $0.name, confidence: $0.confidence) },
            sourceURL: item.sourceURL,
            analyzedAt: item.analysisResult?.analyzedAt
        )

        let url = storage.metadataDir.appendingPathComponent("\(item.id).json")
        do {
            let data = try Self.encoder.encode(sidecar)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[MetadataSidecar] Failed to write sidecar for \(item.id): \(error)")
        }
    }

    func readSidecar(id: String) -> SidecarMetadata? {
        let url = storage.metadataDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(SidecarMetadata.self, from: data)
    }

    func deleteSidecar(id: String) {
        let url = storage.metadataDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Spaces

    /// Write spaces to spaces.json by fetching the current list from the model context.
    /// Use this instead of manually constructing SidecarSpace arrays in views —
    /// it always reflects the latest state after inserts/deletes.
    @MainActor
    func writeSpaces(from context: ModelContext) {
        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)])
        let spaces = (try? context.fetch(descriptor)) ?? []
        writeSpaces(spaces)
    }

    /// Write spaces to spaces.json, automatically including the current all-space guidance from UserDefaults.
    func writeSpaces(_ spaces: [Space]) {
        let sidecars = spaces.map { space in
            SidecarSpace(
                id: space.id,
                name: space.name,
                order: space.order,
                createdAt: space.createdAt,
                customPrompt: space.customPrompt,
                useCustomPrompt: space.useCustomPrompt
            )
        }
        writeSpaceSidecars(sidecars)
    }

    /// Write space sidecars to spaces.json, automatically including the current all-space guidance from UserDefaults.
    func writeSpaceSidecars(_ sidecars: [SidecarSpace]) {
        let allGuidance = UserDefaults.standard.string(forKey: "allSpacePrompt")
        let useAllGuidance = UserDefaults.standard.bool(forKey: "useAllSpacePrompt")
        let file = SidecarSpacesFile(
            spaces: sidecars,
            allSpaceGuidance: allGuidance,
            useAllSpaceGuidance: useAllGuidance
        )
        let url = storage.baseURL.appendingPathComponent("spaces.json")
        do {
            let data = try Self.encoder.encode(file)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[MetadataSidecar] Failed to write spaces.json: \(error)")
        }
    }

    /// Read spaces.json, handling both the new wrapper format and the legacy bare array.
    func readSpacesFile() -> SidecarSpacesFile {
        let url = storage.baseURL.appendingPathComponent("spaces.json")
        guard let data = try? Data(contentsOf: url) else {
            return SidecarSpacesFile(spaces: [], allSpaceGuidance: nil, useAllSpaceGuidance: false)
        }
        // Try wrapper format first
        if let file = try? Self.decoder.decode(SidecarSpacesFile.self, from: data) {
            return file
        }
        // Fall back to legacy bare array
        let spaces = (try? Self.decoder.decode([SidecarSpace].self, from: data)) ?? []
        return SidecarSpacesFile(spaces: spaces, allSpaceGuidance: nil, useAllSpaceGuidance: false)
    }

    /// Legacy convenience — returns just the spaces array.
    func readSpaces() -> [SidecarSpace] {
        readSpacesFile().spaces
    }
}
