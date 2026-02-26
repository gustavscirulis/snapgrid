import SwiftUI

struct EmptyStateView: View {
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.25))

            VStack(spacing: 8) {
                Text("Drop screenshots here")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Or use File \u{2192} Import (\u{2318}O) to get started")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if !KeychainService.exists(service: AIProvider.openai.keychainService) &&
               !KeychainService.exists(service: AIProvider.anthropic.keychainService) &&
               !KeychainService.exists(service: AIProvider.gemini.keychainService) &&
               !KeychainService.exists(service: AIProvider.openrouter.keychainService) {
                VStack(spacing: 8) {
                    Divider()
                        .frame(width: 200)
                        .padding(.vertical, 8)

                    Text("Add an AI API key in Settings (\u{2318},) to enable automatic image analysis")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.snapCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isDragTargeted ? Color.snapAccent : Color.snapBorder, lineWidth: isDragTargeted ? 2 : 1)
                )
        )
    }
}
