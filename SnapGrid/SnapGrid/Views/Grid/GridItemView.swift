import SwiftUI
import AppKit
import AVFoundation

struct GridItemView: View {
    let item: MediaItem
    let width: CGFloat
    let isSelected: Bool
    let spaces: [Space]
    let activeSpaceId: String?
    let selectedCount: Int
    let effectiveIds: Set<String>
    let hiddenItemId: String?
    let onSelect: (CGRect) -> Void
    let onToggleSelect: () -> Void
    let onShiftSelect: () -> Void
    let onDelete: () -> Void
    let onAssignToSpace: (String?) -> Void
    let onRetryAnalysis: () -> Void

    @Environment(VideoPreviewManager.self) private var videoPreview
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var globalFrame: CGRect = .zero
    @State private var hoverTask: Task<Void, Never>?

    init(item: MediaItem, width: CGFloat, isSelected: Bool, spaces: [Space], activeSpaceId: String?, selectedCount: Int, effectiveIds: Set<String>, hiddenItemId: String?, onSelect: @escaping (CGRect) -> Void, onToggleSelect: @escaping () -> Void, onShiftSelect: @escaping () -> Void, onDelete: @escaping () -> Void, onAssignToSpace: @escaping (String?) -> Void, onRetryAnalysis: @escaping () -> Void) {
        self.item = item
        self.width = width
        self.isSelected = isSelected
        self.spaces = spaces
        self.activeSpaceId = activeSpaceId
        self.selectedCount = selectedCount
        self.effectiveIds = effectiveIds
        self.hiddenItemId = hiddenItemId
        self.onSelect = onSelect
        self.onToggleSelect = onToggleSelect
        self.onShiftSelect = onShiftSelect
        self.onDelete = onDelete
        self.onAssignToSpace = onAssignToSpace
        self.onRetryAnalysis = onRetryAnalysis
        _thumbnail = State(initialValue: ImageCacheService.shared.image(forKey: item.id))
    }

    private var height: CGFloat {
        width / item.aspectRatio
    }

    /// Whether this item is part of a multi-selection context menu
    private var isBulk: Bool {
        isSelected && selectedCount > 1
    }

    /// Hover state that stays true while the floating video layer covers this item.
    /// The NSView-backed AVPlayerLayer causes a spurious onHover(false) when it appears
    /// on top; this keeps hover UI visible for the duration of the grid preview.
    private var effectiveHover: Bool {
        isHovered || (item.isVideo && videoPreview.activeItemId == item.id && videoPreview.displayState == .grid)
    }

    /// Whether to show the SwiftUI gradient scrim behind pattern pills.
    /// Suppressed for video items when the floating video layer provides its own CAGradientLayer.
    /// Guarded by `item.isVideo` so non-video items never subscribe to `activeItemId` changes.
    private var showHoverGradient: Bool {
        guard effectiveHover else { return false }
        guard item.isVideo else { return true }
        return videoPreview.activeItemId != item.id
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // LAYER 1: Background selection button
            Button {
                let flags = NSEvent.modifierFlags
                if flags.contains(.command) {
                    onToggleSelect()
                } else if flags.contains(.shift) {
                    onShiftSelect()
                } else {
                    // Pre-claim the video player BEFORE overlay appears —
                    // prevents onHover(false) race from destroying it
                    if item.isVideo {
                        videoPreview.claimForDetail()
                    }
                    onSelect(globalFrame)
                }
            } label: {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.snapMuted)
                            .frame(width: width, height: height)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    }
                }
            }
            .buttonStyle(.plain)

            // LAYER 2: Non-interactive visual overlays
            Group {
                // Video badge (hidden during active preview — floating layer renders video)
                if item.isVideo && videoPreview.activeItemId != item.id {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(8)
                        }
                    }
                    .frame(width: width, height: height)
                }

                // Bottom overlay: analyzing shimmer or hover-only pattern tags
                VStack {
                    Spacer()

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
                                Spacer()
                            }
                            .padding(8)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 6)),
                                removal: .opacity
                            )
                        )
                    } else if item.analysisError == nil, let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                        // Gradient backdrop + staggered pattern tags (hover only)
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [.black.opacity(0.35), .black.opacity(0.1), .clear],
                                startPoint: .bottom,
                                endPoint: .init(x: 0.5, y: 0.55)
                            )
                            .opacity(showHoverGradient ? 1 : 0)
                            .offset(y: effectiveHover ? 0 : 20)
                            .animation(SnapSpring.standard, value: effectiveHover)

                            HStack {
                                FlowLayout(spacing: 5) {
                                    ForEach(Array(patterns.prefix(5).enumerated()), id: \.element.name) { index, pattern in
                                        PatternPill(name: pattern.name)
                                            .opacity(effectiveHover ? 1 : 0)
                                            .offset(y: effectiveHover ? 0 : 8)
                                            .animation(
                                                SnapSpring.fast
                                                    .delay(Double(index) * 0.025),
                                                value: effectiveHover
                                            )
                                    }
                                }
                                Spacer()
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(width: width, height: height, alignment: .bottomLeading)
                .animation(SnapSpring.standard, value: item.isAnalyzing)
            }
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        // LAYER 3: Interactive action buttons as overlays
        .overlay(alignment: .topTrailing) {
            if effectiveHover {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .topLeading) {
            if effectiveHover && activeSpaceId != nil {
                Button { onAssignToSpace(nil) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !item.isAnalyzing && item.analysisError != nil {
                Button(action: onRetryAnalysis) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Retry")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .shadow(  // ImageCard.tsx:96 — shadow-sm / hover:shadow-md
            color: .black.opacity(effectiveHover ? 0.1 : 0.05),
            radius: effectiveHover ? 6 : 2,
            x: 0,
            y: effectiveHover ? 4 : 1
        )
        .animation(SnapSpring.fast, value: effectiveHover)
        .onHover { hovering in
            isHovered = hovering
            hoverTask?.cancel()
            if item.isVideo {
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        videoPreview.startPreview(
                            itemId: item.id,
                            url: MediaStorageService.shared.mediaURL(filename: item.filename),
                            frame: globalFrame,
                            patternNames: item.analysisResult?.patterns.prefix(5).map(\.name) ?? []
                        )
                    }
                } else if videoPreview.activeItemId == item.id {
                    // Floating video layer can cause spurious onHover(false) —
                    // debounce the stop so effectiveHover keeps UI stable.
                    // A genuine hover-in (same or different item) cancels this.
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        videoPreview.stopPreview()
                    }
                } else {
                    videoPreview.stopPreview()
                }
            }
        }
        .onDrag {
            let url = MediaStorageService.shared.mediaURL(filename: item.filename)
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            if let name = item.analysisResult?.patterns.first?.name {
                let ext = url.pathExtension
                provider.suggestedName = ext.isEmpty ? name : "\(name).\(ext)"
            }
            // Register item IDs as plain text for space tab drops
            let idString = "snapgrid:" + effectiveIds.joined(separator: ",")
            provider.registerObject(idString as NSString, visibility: .all)
            return provider
        } preview: {
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96 / item.aspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.snapMuted)
                        .frame(width: 96, height: 64)
                }
                if isBulk {
                    Text("\(selectedCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.snapAccent)
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .opacity(0.85)
        }
        .opacity(item.id == hiddenItemId ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            globalFrame = newValue
            // Keep the floating video layer in sync with scroll/resize
            if item.isVideo && videoPreview.activeItemId == item.id {
                videoPreview.updateGridFrame(newValue)
            }
        }
        .contextMenu {
            // Move to space submenu
            Menu(isBulk ? "Move \(selectedCount) items to" : "Move to") {
                ForEach(spaces) { space in
                    Button {
                        onAssignToSpace(space.id)
                    } label: {
                        if item.space?.id == space.id {
                            Label(space.name, systemImage: "checkmark")
                        } else {
                            Text(space.name)
                        }
                    }
                }
            }

            // Remove from space
            if activeSpaceId != nil {
                Button(isBulk ? "Remove \(selectedCount) from Space" : "Remove from Space") {
                    onAssignToSpace(nil)
                }
            }

            Divider()

            Button("Retry Analysis") {
                onRetryAnalysis()
            }

            Divider()

            Button(isBulk ? "Delete \(selectedCount) Items" : "Delete", role: .destructive) {
                onDelete()
            }
        }
        .task {
            guard thumbnail == nil else { return }
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // Check memory cache first
        if let cached = ImageCacheService.shared.image(forKey: item.id) {
            self.thumbnail = cached
            return
        }

        let storage = MediaStorageService.shared
        let url = storage.thumbnailExists(id: item.id)
            ? storage.thumbnailURL(id: item.id)
            : storage.mediaURL(filename: item.filename)

        if let image = NSImage(contentsOf: url) {
            ImageCacheService.shared.setImage(image, forKey: item.id)
            self.thumbnail = image
        }
    }
}

// MARK: - Shimmer Text

/* ─────────────────────────────────────────────────────────
 * SHIMMER ANIMATION
 *
 * A bright band sweeps left → right across the text in a
 * 2.5s cycle. The gradient starts fully off-screen left
 * (-0.6) and exits fully off-screen right (1.6), so the
 * highlight enters and leaves smoothly with no pop-in.
 * The loop-point jump is invisible (both ends off-screen).
 *
 * Gradient band width: 0.8 (phase ± 0.4)
 * Brightness:  base 0.5 → peak 1.0 → base 0.5
 * ───────────────────────────────────────────────────────── */

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
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: ShimmerConfig.cycle)
                / ShimmerConfig.cycle
            let phase = t * (ShimmerConfig.rangeEnd - ShimmerConfig.rangeStart)
                + ShimmerConfig.rangeStart

            Text(text)
                .font(.system(size: 11))
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

