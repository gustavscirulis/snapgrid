import Foundation

extension Sequence where Element == Space {
    func membershipSorted() -> [Space] {
        Array(self).sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

extension MediaItem {
    var space: Space? {
        get { orderedSpaces.first }
        set {
            if let newValue {
                setMembership([newValue])
            } else {
                _ = clearSpaces()
            }
        }
    }

    var orderedSpaces: [Space] {
        spaces.membershipSorted()
    }

    var orderedSpaceIDs: [String] {
        orderedSpaces.map(\.id)
    }

    func belongs(to spaceId: String) -> Bool {
        spaces.contains { $0.id == spaceId }
    }

    func setMembership(_ newSpaces: [Space]) {
        spaces = newSpaces.membershipSorted()
    }

    @discardableResult
    func addSpace(_ space: Space) -> Bool {
        guard !belongs(to: space.id) else { return false }
        spaces.append(space)
        spaces = spaces.membershipSorted()
        return true
    }

    @discardableResult
    func removeSpace(id: String) -> Bool {
        let originalCount = spaces.count
        spaces.removeAll { $0.id == id }
        return spaces.count != originalCount
    }

    @discardableResult
    func toggleSpace(_ space: Space) -> Bool {
        if removeSpace(id: space.id) {
            return false
        }
        spaces.append(space)
        spaces = spaces.membershipSorted()
        return true
    }

    @discardableResult
    func clearSpaces() -> Bool {
        guard !spaces.isEmpty else { return false }
        spaces.removeAll()
        return true
    }
}

enum SpaceGuidanceResolver {
    static func resolve(for item: MediaItem) -> (guidance: String?, spaceContext: String?) {
        resolve(for: item.orderedSpaces)
    }

    static func resolve(for spaces: [Space]) -> (guidance: String?, spaceContext: String?) {
        let orderedSpaces = spaces.membershipSorted()

        let prompts: [String] = orderedSpaces.compactMap { space -> String? in
            guard space.useCustomPrompt,
                  let prompt = space.customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !prompt.isEmpty else { return nil }
            return prompt
        }

        let guidance: String?
        if prompts.isEmpty {
            let allGuidance = UserDefaults.standard.string(forKey: "allSpacePrompt")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if UserDefaults.standard.bool(forKey: "useAllSpacePrompt"),
               let allGuidance,
               !allGuidance.isEmpty {
                guidance = allGuidance
            } else {
                guidance = nil
            }
        } else {
            guidance = prompts.joined(separator: "\n\n")
        }

        let names = orderedSpaces.map(\.name)
        let spaceContext: String?
        switch names.count {
        case 0:
            spaceContext = nil
        case 1:
            spaceContext = "This image belongs to a collection called \"\(names[0])\". Use this as context to inform your analysis."
        default:
            let joinedNames = names.map { "\"\($0)\"" }.joined(separator: ", ")
            spaceContext = "This image belongs to collections called \(joinedNames). Use these as context to inform your analysis."
        }

        return (guidance, spaceContext)
    }
}
