import AppKit
import Foundation

// MARK: - Chat Message Types (ephemeral, not persisted)

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    var content: [ChatContent]
    let timestamp = Date()
    var isStreaming: Bool = false
}

enum MessageRole: Sendable {
    case user, assistant
}

enum ChatContent {
    case text(String)
    case image(mediaItemId: String, thumbnail: NSImage?)
    case toolCall(id: String, name: String, status: ToolCallStatus)
    case error(String)
}

enum ToolCallStatus: Sendable {
    case running, completed, failed
}
