import SwiftUI

struct ChatInputBar: View {
    let isProcessing: Bool
    let spaceName: String?
    let onSend: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                if let spaceName {
                    Text("Asking in: \(spaceName)")
                        .font(.caption)
                        .foregroundStyle(Color.snapMutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    TextField("Ask about your images...", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isFocused)
                        .onSubmit {
                            send()
                        }

                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(canSend ? Color.snapAccent : Color.snapMutedForeground.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
                .padding(10)
                .background(Color.snapMuted.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(12)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }
        onSend(trimmed)
        text = ""
    }
}
