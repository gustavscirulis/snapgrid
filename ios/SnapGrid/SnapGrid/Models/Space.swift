import Foundation
import SwiftData

@Model
class Space {
    @Attribute(.unique) var id: String
    var name: String
    var order: Int
    var createdAt: Date
    var customPrompt: String?
    var useCustomPrompt: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \MediaItem.space)
    var items: [MediaItem] = []

    init(id: String = UUID().uuidString, name: String, order: Int, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.order = order
        self.createdAt = createdAt
    }
}
