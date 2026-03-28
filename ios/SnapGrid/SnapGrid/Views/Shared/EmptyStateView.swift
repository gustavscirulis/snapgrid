import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            Text("No images yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            Text("Add images to your SnapGrid library\non your Mac to see them here")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }
}

struct SearchEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            Text("No results found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            Text("Something went wrong")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await retry() }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }
}
