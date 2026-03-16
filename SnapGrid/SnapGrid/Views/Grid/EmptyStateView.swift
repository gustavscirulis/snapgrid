import SwiftUI

struct EmptyStateView: View {
    @State private var isDragTargeted = false

    // Random-looking heights for skeleton placeholders
    private let skeletonHeights: [CGFloat] = [
        180, 260, 200, 320, 150, 280, 220, 300,
        170, 250, 190, 340, 160, 270, 210, 290,
        240, 180, 310, 200, 260, 170, 230, 280,
    ]

    var body: some View {
        GeometryReader { geometry in
            let columns = max(2, Int(geometry.size.width / 220))
            let spacing: CGFloat = 16  // Match MasonryGridView spacing
            let totalSpacing = spacing * CGFloat(columns - 1) + 32  // 16px padding each side
            let columnWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

            ZStack {
                // Skeleton placeholders behind
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        VStack(spacing: spacing) {
                            ForEach(0..<3, id: \.self) { row in
                                let index = col * 3 + row
                                let h = skeletonHeights[index % skeletonHeights.count]
                                RoundedRectangle(cornerRadius: 12)  // Match GridItemView radius
                                    .fill(Color.snapMuted.opacity(0.5))
                                    .frame(width: columnWidth, height: h)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)  // Match grid padding
                .opacity(0.5)

                // Onboarding card centered on top
                VStack(spacing: 24) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.snapMutedForeground.opacity(0.5))  // EmptyStateCard.tsx — adaptive icon

                    VStack(spacing: 8) {
                        Text("Drop screenshots here")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.snapForeground)  // EmptyStateCard.tsx — text-gray-700 dark:text-gray-200

                        Text("Or use File \u{2192} Import (\u{2318}O) to get started")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.snapMutedForeground)  // EmptyStateCard.tsx — text-gray-500 dark:text-gray-400
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
                                .foregroundStyle(Color.snapMutedForeground.opacity(0.7))
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
    }
}
