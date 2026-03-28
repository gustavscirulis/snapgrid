import Foundation

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

// MARK: - Service

final class MetadataSidecarService: Sendable {

    static let shared = MetadataSidecarService()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Item Sidecars

    func writeSidecar(for item: MediaItem) {
        let storage = MediaStorageService.shared
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
            patterns: item.analysisResult?.patterns.map { SidecarPattern(name: $0.name, confidence: $0.confidence) }
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
        let url = MediaStorageService.shared.metadataDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(SidecarMetadata.self, from: data)
    }

    func deleteSidecar(id: String) {
        let url = MediaStorageService.shared.metadataDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Spaces

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

    func writeSpaceSidecars(_ sidecars: [SidecarSpace]) {
        let url = MediaStorageService.shared.baseURL.appendingPathComponent("spaces.json")
        do {
            let data = try Self.encoder.encode(sidecars)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[MetadataSidecar] Failed to write spaces.json: \(error)")
        }
    }

    func readSpaces() -> [SidecarSpace] {
        let url = MediaStorageService.shared.baseURL.appendingPathComponent("spaces.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder.decode([SidecarSpace].self, from: data)) ?? []
    }
}
