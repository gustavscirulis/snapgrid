import Foundation

struct SpacesManager {
    let rootURL: URL

    func loadSpaces() throws -> [Space] {
        let spacesURL = rootURL.appendingPathComponent("spaces.json")

        guard FileManager.default.fileExists(atPath: spacesURL.path) else {
            return []
        }

        let data = try Data(contentsOf: spacesURL)
        let spaces = try JSONDecoder().decode([Space].self, from: data)
        return spaces.sorted { $0.order < $1.order }
    }

    /// Derive spaces from metadata when spaces.json doesn't exist yet.
    /// Returns unnamed spaces grouped by spaceId.
    func deriveSpaces(from items: [SnapGridItem]) -> [Space] {
        let spaceIds = Set(items.compactMap(\.spaceId))
        return spaceIds.enumerated().map { index, id in
            Space(
                id: id,
                name: "Space \(index + 1)",
                order: index,
                createdAt: ""
            )
        }
    }
}
