import SwiftUI

struct EmptyStateView: View {

    // Varied heights for skeleton placeholders (matches Mac app pattern)
    private let skeletonHeights: [CGFloat] = [
        180, 260, 200, 320, 150, 280, 220, 300,
        170, 250, 190, 340, 160, 270, 210, 290,
    ]

    private let columns = 2
    private let spacing: CGFloat = 8    // Match MasonryGrid
    private let padding: CGFloat = 12   // Match grid horizontal padding

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = spacing * CGFloat(columns - 1) + padding * 2
            let columnWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

            // Ghost grid background — aligned to top
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<columns, id: \.self) { col in
                    VStack(spacing: spacing) {
                        ForEach(0..<4, id: \.self) { row in
                            let index = col * 4 + row
                            let h = skeletonHeights[index % skeletonHeights.count]
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.snapDarkMuted.opacity(0.5))
                                .frame(width: columnWidth, height: h)
                        }
                    }
                }
            }
            .padding(.horizontal, padding)
            .opacity(0.5)

            // Centered onboarding card — positioned at the center of the visible area
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))

                VStack(spacing: 8) {
                    Text("Add images or videos")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Tap + to import from Photos,\nor share from any app")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .frame(maxWidth: geometry.size.width - 48)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.snapDarkCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.snapDarkBorder, lineWidth: 1)
                    )
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SearchEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            Text("No results found")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlaceholderView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .accessibilityElement(children: .combine)
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
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await retry() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }
}
