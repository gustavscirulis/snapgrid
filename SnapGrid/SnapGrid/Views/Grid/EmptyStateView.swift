import SwiftUI

struct EmptyStateView: View {
    enum Mode {
        case appLevel
        case spaceLevel
    }

    var mode: Mode = .appLevel
    var electronLibraryDetected: Bool = false
    var isDragTargeted: Bool = false

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
                                    .fill(Color(nsColor: .quaternaryLabelColor))
                                    .frame(width: columnWidth, height: h)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .opacity(0.5)

                // Onboarding card centered on top
                VStack(spacing: 24) {
                    Image(systemName: mode == .appLevel ? "photo.on.rectangle.angled" : "rectangle.stack.badge.plus")
                        .font(.system(size: 56, weight: .light))  // Decorative icon — fixed size intentional
                        .foregroundStyle(.tertiary)

                    VStack(spacing: 8) {
                        Text(mode == .appLevel ? "Add images or videos" : "No items in this space")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(mode == .appLevel ? "Drop files here, or use File \u{2192} Import (\u{2318}O)" : "Drop images here or move items from All")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    if mode == .appLevel {
                        if electronLibraryDetected {
                            Button("Import from SnapGrid") {
                                NotificationCenter.default.post(name: .importElectronLibrary, object: nil)
                            }
                            .controlSize(.large)
                        } else {
                            Button("Import") {
                                NotificationCenter.default.post(name: .importFolder, object: nil)
                            }
                            .controlSize(.large)
                        }
                    }

                    if mode == .appLevel,
                       !KeychainService.exists(service: AIProvider.openai.keychainService),
                       !KeychainService.exists(service: AIProvider.anthropic.keychainService),
                       !KeychainService.exists(service: AIProvider.gemini.keychainService),
                       !KeychainService.exists(service: AIProvider.openrouter.keychainService) {
                        VStack(spacing: 12) {
                            Divider()
                                .frame(width: 160)

                            Text("Add an AI API key in Settings (\u{2318},) to enable automatic image analysis")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                        }
                    }
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThickMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isDragTargeted ? Color.snapAccent : Color(nsColor: .separatorColor), lineWidth: isDragTargeted ? 2 : 1)
                        )
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}
