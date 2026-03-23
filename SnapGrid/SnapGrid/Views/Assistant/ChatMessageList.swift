import SwiftUI

struct ChatMessageList: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(SnapSpring.fast) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Group content into sections: text, tool calls, image grids, errors
                ForEach(Array(groupedContent.enumerated()), id: \.offset) { _, group in
                    switch group {
                    case .text(let text):
                        textBubble(text)
                    case .images(let images):
                        imageGrid(images)
                    case .toolCall(let id, let name, let status):
                        toolCallPill(id: id, name: name, status: status)
                    case .error(let text):
                        errorView(text)
                    }
                }
            }

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    // Group consecutive images together for grid display
    private var groupedContent: [ContentGroup] {
        var groups: [ContentGroup] = []
        var pendingImages: [(String, NSImage)] = []

        func flushImages() {
            if !pendingImages.isEmpty {
                groups.append(.images(pendingImages))
                pendingImages = []
            }
        }

        for content in message.content {
            switch content {
            case .text(let text):
                flushImages()
                if !text.isEmpty {
                    groups.append(.text(text))
                }
            case .image(let mediaItemId, let thumbnail):
                if let thumbnail {
                    pendingImages.append((mediaItemId, thumbnail))
                }
            case .toolCall(let id, let name, let status):
                flushImages()
                groups.append(.toolCall(id: id, name: name, status: status))
            case .error(let text):
                flushImages()
                groups.append(.error(text))
            }
        }

        flushImages()
        return groups
    }

    // MARK: - Content Views

    @ViewBuilder
    private func textBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(message.role == .user ? .white : Color.snapForeground)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.role == .user ? Color.snapAccent : Color.snapCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func imageGrid(_ images: [(String, NSImage)]) -> some View {
        let columns = images.count == 1 ? 1 : 2
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)

        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, pair in
                let (_, image) = pair
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minHeight: 60, maxHeight: images.count == 1 ? 200 : 120)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func toolCallPill(id: String, name: String, status: ToolCallStatus) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }

            Text(toolDisplayName(name, status: status))
                .font(.caption)
                .foregroundStyle(Color.snapMutedForeground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.snapMuted.opacity(0.5))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func errorView(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.snapMutedForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.snapMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toolDisplayName(_ name: String, status: ToolCallStatus) -> String {
        let past = status == .completed || status == .failed
        switch name {
        case "search_library": return past ? "Searched library" : "Searching library..."
        case "get_image": return past ? "Loaded image" : "Loading image..."
        case "analyze_image": return past ? "Analyzed image" : "Analyzing image..."
        default: return name
        }
    }
}

// MARK: - Content Grouping

private enum ContentGroup {
    case text(String)
    case images([(String, NSImage)])  // (mediaItemId, thumbnail)
    case toolCall(id: String, name: String, status: ToolCallStatus)
    case error(String)
}
