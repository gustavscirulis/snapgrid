import SwiftUI
import AVKit

struct ImageDetailView: View {
    let item: SnapGridItem
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.snapDarkBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Media
                    if item.isVideo, let url = item.mediaURL {
                        VideoPlayer(player: AVPlayer(url: url))
                            .aspectRatio(item.aspectRatio, contentMode: .fit)
                    } else if let image {
                        ZoomableImageView(image: image)
                            .aspectRatio(item.aspectRatio, contentMode: .fit)
                    } else if isLoading {
                        Rectangle()
                            .fill(Color.snapDarkMuted)
                            .aspectRatio(item.aspectRatio, contentMode: .fit)
                            .overlay {
                                ProgressView()
                                    .tint(.white.opacity(0.3))
                            }
                    }

                    // Metadata panel
                    MetadataPanel(item: item)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadFullImage()
        }
    }

    private func loadFullImage() async {
        guard let url = item.mediaURL, !item.isVideo else {
            isLoading = false
            return
        }
        image = await ThumbnailCache.shared.loadImage(for: url)
        isLoading = false
    }
}

struct MetadataPanel: View {
    let item: SnapGridItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pattern tags
            if let patterns = item.patterns, !patterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Patterns")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)

                    FlowLayout(spacing: 6) {
                        ForEach(patterns, id: \.name) { pattern in
                            HStack(spacing: 4) {
                                Text(pattern.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(Int(pattern.confidence * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.snapDarkMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            // AI Context
            if let context = item.imageContext, !context.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Analysis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)

                    Text(context)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(4)
                }
            }

            // Technical details
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)

                HStack(spacing: 16) {
                    DetailChip(label: "Size", value: "\(item.width) × \(item.height)")
                    DetailChip(label: "Type", value: item.isVideo ? "Video" : "Image")
                    if let duration = item.duration {
                        DetailChip(label: "Duration", value: String(format: "%.1fs", duration))
                    }
                }

                if let date = item.createdDate {
                    DetailChip(
                        label: "Added",
                        value: date.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            Spacer(minLength: 40)
        }
    }
}

private struct DetailChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
