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
    var spaces: [Space] = []
    let width: CGFloat
    var isSelected: Bool = false
    var onSelect: ((MediaItem, CGRect, UIImage?) -> Void)?
    var onRetryAnalysis: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?
    var onAssignToSpace: ((String, String?) -> Void)?
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
                        VStack(spacing: 8) {
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
                        .padding(8)
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
                        shimmerBadge
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
        .overlay(alignment: .bottomLeading) {
            if !item.isAnalyzing && item.analysisError != nil {
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
                    .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
                    .contentShape(Rectangle())
                }
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
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

            if !spaces.isEmpty {
                Menu {
                    ForEach(spaces) { space in
                        Button {
                            onAssignToSpace?(item.id, space.id)
                        } label: {
                            if item.belongs(to: space.id) {
                                Label(space.name, systemImage: "checkmark")
                            } else {
                                Text(space.name)
                            }
                        }
                    }
                    if !item.spaces.isEmpty {
                        Divider()
                        Button {
                            onAssignToSpace?(item.id, nil)
                        } label: {
                            Label("Remove from All Spaces", systemImage: "folder.badge.minus")
                        }
                    }
                } label: {
                    Label("Update Spaces", systemImage: "folder.badge.plus")
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
        .onChange(of: isSelected) { wasSelected, isNowSelected in
            // Retry thumbnail load after returning from full-screen overlay
            // if the iCloud file has since downloaded
            if wasSelected && !isNowSelected && thumbnail == nil {
                Task { await loadThumbnail() }
            }
        }
    }

    // MARK: - Thumbnail Loading

    @ViewBuilder
    private var shimmerBadge: some View {
        let base = ShimmerText("Analyzing...")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

        if #available(iOS 26, *) {
            base
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        } else {
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        }
    }

    private func loadThumbnail(isRetry: Bool = false) async {
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

        // Auto-retry once after a short delay — iCloud files may arrive
        // just after the initial load attempt
        if !isRetry {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await loadThumbnail(isRetry: true)
        } else {
            loadFailed = true
        }
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
