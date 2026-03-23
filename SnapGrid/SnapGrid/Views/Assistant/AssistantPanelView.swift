import SwiftUI

struct AssistantPanelView: View {
    @Bindable var chatService: ChatService
    let context: ChatContext
    let spaceName: String?
    let onClose: () -> Void

    private var hasApiKey: Bool {
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
        return (try? KeychainService.get(service: provider.keychainService)) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Assistant")
                    .font(.headline)
                    .foregroundStyle(Color.snapForeground)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.snapMutedForeground)
                        .frame(width: 24, height: 24)
                        .background(Color.snapMuted.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // API key warning
            if !hasApiKey {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("Add an API key in Settings to use the assistant.")
                        .font(.caption)
                        .foregroundStyle(Color.snapMutedForeground)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.snapMuted.opacity(0.3))
            }

            // Messages or empty state
            if chatService.messages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.snapMutedForeground.opacity(0.5))
                    Text("Ask me about your image library")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.snapMutedForeground)
                    Text("I can search, show images, and analyze visual details.")
                        .font(.caption)
                        .foregroundStyle(Color.snapMutedForeground.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                Spacer()
            } else {
                ChatMessageList(messages: chatService.messages)
            }

            // Input bar
            ChatInputBar(
                isProcessing: chatService.isProcessing,
                spaceName: spaceName
            ) { text in
                chatService.sendMessage(text, context: context)
            }
        }
        .background(Color.snapBackground)
    }
}
