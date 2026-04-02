import SwiftUI

struct GridItemRectsPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        // When multiple grids exist (space pages in a horizontal pager),
        // prefer rects that are on the visible screen over off-screen ones.
        let screen = UIScreen.main.bounds
        value.merge(nextValue()) { existing, new in
            if screen.intersects(new) { return new }
            return existing
        }
    }
}

struct GridItemView: View {
    let item: MediaItem
    let width: CGFloat
    var isSelected: Bool = false
    var onSelect: ((MediaItem, CGRect, UIImage?) -> Void)?
    var onRetryAnalysis: (() -> Void)?
    var onShare: (() -> Void)?
    var onRemoveFromSpace: (() -> Void)?
    var onDelete: (() -> Void)?
    @State private var thumbnail: UIImage?
    @State private var loadFailed = false

    private var height: CGFloat {
        width / item.gridAspectRatio
    }

    /// Target pixel width for thumbnail downsampling (@2x for retina)
    private var targetPixelWidth: CGFloat {
        width * 2
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail image
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
                    .transition(.opacity)
            } else if loadFailed {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: width, height: height)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Tap to retry")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .onTapGesture {
                        loadFailed = false
                        Task { await loadThumbnail() }
                    }
            } else {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: width, height: height)
            }

            // Video indicator
            if item.isVideo {
                HStack {
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)
            }

            // Analysis state overlay
            if item.isAnalyzing {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [.black.opacity(0.5), .black.opacity(0.15), .clear],
                        startPoint: .bottom,
                        endPoint: .init(x: 0.5, y: 0.3)
                    )

                    HStack {
                        ShimmerText("Analyzing...")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .environment(\.colorScheme, .dark)
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(width: width, height: height)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    )
                )
            } else if !item.isAnalyzing && item.analysisError != nil {
                Button {
                    onRetryAnalysis?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                        Text("Retry")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .padding(8)
                .frame(width: width, height: height, alignment: .bottomLeading)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: width, height: height)
        .animation(SnapSpring.resolvedStandard, value: item.isAnalyzing)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(item.isVideo ? "Video" : "Image")
        .accessibilityHint("Double tap to view full screen")
        .opacity(isSelected ? 0 : 1)
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let frame = geo.frame(in: .global)
                        onSelect?(item, frame, thumbnail)
                    }
                    .preference(
                        key: GridItemRectsPreferenceKey.self,
                        value: [item.id: geo.frame(in: .global)]
                    )
            }
        )
        .contextMenu {
            Button {
                onShare?()
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }

            Button {
                onRetryAnalysis?()
            } label: {
                Label("Redo Analysis", systemImage: "arrow.clockwise")
            }

            if let onRemoveFromSpace {
                Button {
                    onRemoveFromSpace()
                } label: {
                    Label("Remove from Space", systemImage: "folder.badge.minus")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        let cache = ThumbnailCache.shared

        // Try thumbnail first (fast, no wait)
        if let thumbURL = item.thumbnailURL {
            let (loaded, wasCached) = await cache.loadImage(for: thumbURL, targetPixelWidth: targetPixelWidth)
            if let loaded {
                if wasCached {
                    thumbnail = loaded
                } else {
                    withAnimation(.easeIn(duration: 0.25)) {
                        thumbnail = loaded
                    }
                }
                return
            }
        }

        // Fall back to media file (wait for iCloud download if needed)
        if let mediaURL = item.mediaURL {
            let (loaded, wasCached) = await cache.loadImageWhenReady(for: mediaURL, timeout: 180, targetPixelWidth: targetPixelWidth)
            if let loaded {
                if wasCached {
                    thumbnail = loaded
                } else {
                    withAnimation(.easeIn(duration: 0.25)) {
                        thumbnail = loaded
                    }
                }
                return
            }
        }

        loadFailed = true
    }
}

// MARK: - Shimmer Text

private enum ShimmerConfig {
    static let cycle: Double = 1.5     // seconds per sweep
    static let bandHalf: CGFloat = 0.4 // half-width of bright band
    static let rangeStart: CGFloat = -0.6
    static let rangeEnd: CGFloat = 1.6
    static let baseBrightness: CGFloat = 0.5
    static let peakBrightness: CGFloat = 1.0
}

struct ShimmerText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if UIAccessibility.isReduceMotionEnabled {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: ShimmerConfig.cycle)
                    / ShimmerConfig.cycle
                let phase = t * (ShimmerConfig.rangeEnd - ShimmerConfig.rangeStart)
                    + ShimmerConfig.rangeStart

                Text(text)
                    .font(.caption2)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                .white.opacity(ShimmerConfig.baseBrightness),
                                .white.opacity(ShimmerConfig.peakBrightness),
                                .white.opacity(ShimmerConfig.baseBrightness),
                            ],
                            startPoint: .init(x: phase - ShimmerConfig.bandHalf, y: 0.5),
                            endPoint: .init(x: phase + ShimmerConfig.bandHalf, y: 0.5)
                        )
                    )
            }
        }
    }
}
