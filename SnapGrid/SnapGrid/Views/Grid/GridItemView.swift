import SwiftUI
import AppKit
import AVFoundation

struct GridItemView: View {
    let item: MediaItem
    let width: CGFloat
    let spaces: [Space]
    let activeSpaceId: String?
    let onSelect: (CGRect) -> Void
    let onToggleSelect: () -> Void
    let onShiftSelect: () -> Void
    let onDelete: (Set<String>) -> Void
    let onChangeSpaceMembership: (Set<String>, SpaceMembershipAction) -> Void
    let onRetryAnalysis: (Set<String>) -> Void
    let onShare: (Set<String>, CGRect) -> Void

    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var globalFrame: CGRect = .zero
    @State private var hoverTask: Task<Void, Never>?
    /// Suppresses the first `.onHover(false)` after a video preview starts.
    /// The floating NSView (AVPlayerLayer) causes a spurious exit event
    /// that macOS never corrects with a re-entry.
    @State private var suppressHoverExit = false

    // Eagerly resolved SwiftData properties — prevents faults on detached backing stores
    // when SwiftUI re-evaluates the body (e.g. for context menu snapshots).
    private let itemIsVideo: Bool
    private let itemSpaceIds: [String]
    private let itemAspectRatio: CGFloat

    // Selection state derived from AppState — changes only invalidate this view,
    // not the parent MasonryGridView (which no longer depends on selectedIds).
    private var isSelected: Bool { appState.selectedIds.contains(item.id) }
    private var selectedCount: Int { appState.selectedIds.count }
    private var effectiveIds: Set<String> {
        isSelected && selectedCount > 1 ? appState.selectedIds : [item.id]
    }

    init(item: MediaItem, width: CGFloat, spaces: [Space], activeSpaceId: String?, onSelect: @escaping (CGRect) -> Void, onToggleSelect: @escaping () -> Void, onShiftSelect: @escaping () -> Void, onDelete: @escaping (Set<String>) -> Void, onChangeSpaceMembership: @escaping (Set<String>, SpaceMembershipAction) -> Void, onRetryAnalysis: @escaping (Set<String>) -> Void, onShare: @escaping (Set<String>, CGRect) -> Void) {
        self.item = item
        self.width = width
        self.spaces = spaces
        self.activeSpaceId = activeSpaceId
        self.onSelect = onSelect
        self.onToggleSelect = onToggleSelect
        self.onShiftSelect = onShiftSelect
        self.onDelete = onDelete
        self.onChangeSpaceMembership = onChangeSpaceMembership
        self.onRetryAnalysis = onRetryAnalysis
        self.onShare = onShare
        self.itemIsVideo = item.isVideo
        self.itemSpaceIds = item.orderedSpaceIDs
        self.itemAspectRatio = item.aspectRatio
        _thumbnail = State(initialValue: ImageCacheService.shared.image(forKey: item.id))
    }

    private var height: CGFloat {
        width / itemAspectRatio
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if itemIsVideo { parts.append("Video") } else { parts.append("Image") }
        if let summary = item.analysisResult?.imageSummary, !summary.isEmpty {
            parts.append(summary)
        }
        parts.append("\(item.width) by \(item.height)")
        if item.isAnalyzing { parts.append("Analyzing") }
        if item.analysisError != nil { parts.append("Analysis failed") }
        return parts.joined(separator: ", ")
    }

    private var gridItemOpacity: Double {
        item.id == appState.detailItem ? 0 : 1
    }

    private var deleteStage: Int {
        appState.deleteStage(for: item.id)
    }

    /// Whether this item is part of a multi-selection context menu
    private var isBulk: Bool {
        isSelected && selectedCount > 1
    }

    private var isInActiveSpace: Bool {
        guard let activeSpaceId else { return false }
        return itemSpaceIds.contains(activeSpaceId)
    }

    /// Hover state that stays true while the floating video layer covers this item.
    /// The NSView-backed AVPlayerLayer causes a spurious onHover(false) when it appears
    /// on top; this keeps hover UI visible for the duration of the grid preview.
    private var effectiveHover: Bool {
        isHovered || (itemIsVideo && videoPreview.activeItemId == item.id && videoPreview.displayState == .grid)
    }

    /// Whether to show the SwiftUI gradient scrim behind pattern pills.
    /// Suppressed for video items when the floating video layer provides its own CAGradientLayer.
    /// Guarded by `itemIsVideo` so non-video items never subscribe to `activeItemId` changes.
    private var showHoverGradient: Bool {
        guard effectiveHover else { return false }
        guard itemIsVideo else { return true }
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
                if itemIsVideo && videoPreview.activeItemId != item.id {
                    VStack {
                        Spacer()
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
                    }
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
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
                                shimmerBadge
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
                            .offset(y: effectiveHover ? 0 : (reduceMotion ? 0 : 20))
                            .animation(SnapSpring.standard(reduced: reduceMotion), value: effectiveHover)

                            HStack {
                                FlowLayout(spacing: 4) {
                                    ForEach(Array(patterns.prefix(5).enumerated()), id: \.element.name) { index, pattern in
                                        PatternPill(name: pattern.name, useGlass: false)
                                            .opacity(effectiveHover ? 1 : 0)
                                            .offset(y: effectiveHover ? 0 : (reduceMotion ? 0 : 8))
                                            .animation(
                                                reduceMotion
                                                    ? .easeInOut(duration: 0.1)
                                                    : SnapSpring.fast.delay(Double(index) * 0.025),
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
                .animation(SnapSpring.standard(reduced: reduceMotion), value: item.isAnalyzing)
            }
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        // LAYER 3: Interactive action buttons as overlays
        .overlay(alignment: .topTrailing) {
            if effectiveHover {
                Button { onDelete(effectiveIds) } label: {
                    hoverButtonIcon("trash", size: 10)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Delete")
                .accessibilityHint("Moves this item to the trash")
            }
        }
        .overlay(alignment: .topLeading) {
            if effectiveHover && isInActiveSpace, let activeSpaceId {
                Button { onChangeSpaceMembership(effectiveIds, .remove(activeSpaceId)) } label: {
                    hoverButtonIcon("folder.badge.minus", size: 10)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Remove from space")
                .accessibilityHint("Removes this item from the current space")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !item.isAnalyzing && item.analysisError != nil {
                Button { onRetryAnalysis(effectiveIds) } label: {
                    retryBadge
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Redo analysis")
                .accessibilityHint("Runs AI analysis again on this item")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Delete animation — wallet card crush (mask approach)
        .mask {
            let maskH = deleteStage >= 1 ? height * CardCrush.crushedScaleY : height
            let maskW = deleteStage >= 2 ? width * CardCrush.crushedScaleX : width
            RoundedRectangle(cornerRadius: 12)
                .frame(width: maskW, height: maskH)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected && deleteStage == 0 ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: .black.opacity(deleteStage > 0 ? 0 : (effectiveHover ? 0.1 : 0.05)),
            radius: effectiveHover ? 6 : 2,
            x: 0,
            y: effectiveHover ? 4 : 1
        )
        .animation(SnapSpring.fast(reduced: reduceMotion), value: effectiveHover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHidden(deleteStage > 0)
        .onHover { hovering in
            guard deleteStage == 0 else {
                isHovered = false
                return
            }
            isHovered = hovering
            hoverTask?.cancel()
            if itemIsVideo {
                if hovering {
                    // Don't start preview during rubber band selection or drag
                    guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                    suppressHoverExit = false
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        // Only arm the suppress flag when actually creating a new preview —
                        // re-entering an already-previewing item won't spawn a new layer.
                        if videoPreview.activeItemId != item.id {
                            suppressHoverExit = true
                        }
                        videoPreview.startPreview(
                            itemId: item.id,
                            url: MediaStorageService.shared.mediaURL(filename: item.filename),
                            frame: globalFrame,
                            patternNames: item.analysisResult?.patterns.prefix(5).map(\.name) ?? []
                        )
                    }
                } else if videoPreview.activeItemId == item.id {
                    // The floating NSView causes one spurious onHover(false) when it
                    // first appears. Suppress that single exit; subsequent exits are genuine.
                    if suppressHoverExit {
                        suppressHoverExit = false
                        if mouseIsInsideGridItem() {
                            // Genuinely spurious exit — poll for real exit since
                            // macOS won't send another onHover(false).
                            hoverTask = Task {
                                while !Task.isCancelled {
                                    try? await Task.sleep(for: .milliseconds(100))
                                    guard !Task.isCancelled else { return }
                                    if !mouseIsInsideGridItem() {
                                        videoPreview.stopPreview()
                                        return
                                    }
                                }
                            }
                            return
                        }
                        // Mouse already left — fall through to delayed stopPreview
                    }
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
            appState.isDraggingFromApp = true
            let url = MediaStorageService.shared.mediaURL(filename: item.filename)
            // Build provider from scratch — NSItemProvider(contentsOf:) creates a sealed
            // provider where additional registerObject() calls are not loadable by the
            // drop system (the types appear in registeredTypeIdentifiers but data loading fails).
            let provider = NSItemProvider()
            provider.registerObject(url as NSURL, visibility: .all)
            let idString = "snapgrid:" + effectiveIds.joined(separator: ",")
            provider.registerObject(idString as NSString, visibility: .all)
            if let name = item.analysisResult?.patterns.first?.name {
                let ext = url.pathExtension
                provider.suggestedName = ext.isEmpty ? name : "\(name).\(ext)"
            }
            return provider
        } preview: {
            DragThumbnailPreview(
                image: thumbnail,
                aspectRatio: itemAspectRatio,
                bulkCount: isBulk ? selectedCount : nil
            )
        }
        .opacity(deleteStage >= 2 ? 0 : gridItemOpacity)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            // Deadband — skip state write when frame barely moved (< 1pt).
            // Reduces @State churn for all visible items during scroll.
            guard abs(newValue.origin.x - globalFrame.origin.x) > 1 ||
                  abs(newValue.origin.y - globalFrame.origin.y) > 1 ||
                  abs(newValue.size.width - globalFrame.size.width) > 1 ||
                  abs(newValue.size.height - globalFrame.size.height) > 1 else { return }
            globalFrame = newValue
            // Keep the floating video layer in sync with scroll/resize
            if itemIsVideo && videoPreview.activeItemId == item.id {
                videoPreview.updateGridFrame(newValue)
            }
            // Keep detail source frame in sync when this item is the active detail
            if appState.detailItem == item.id {
                appState.detailSourceFrame = newValue
            }
        }
        .onChange(of: appState.detailItem) { oldId, newId in
            if newId == item.id {
                appState.detailSourceFrame = globalFrame
            } else if oldId == item.id {
                // Detail dismissed — mouse may have moved, so clear stale hover state.
                isHovered = false
                suppressHoverExit = false
            }
        }
        .contextMenu {
            let removeFromActiveSpace: (() -> Void)? = {
                guard let activeSpaceId, itemSpaceIds.contains(activeSpaceId) else {
                    return nil
                }
                return { onChangeSpaceMembership(effectiveIds, .remove(activeSpaceId)) }
            }()

            MediaItemContextMenu(
                spaces: spaces,
                activeSpaceId: activeSpaceId,
                currentSpaceIds: itemSpaceIds,
                bulkCount: isBulk ? selectedCount : nil,
                onToggleSpace: { spaceId in
                    onChangeSpaceMembership(effectiveIds, .toggle(spaceId))
                },
                onRemoveFromActiveSpace: removeFromActiveSpace,
                onShare: { onShare(effectiveIds, globalFrame) },
                onRedoAnalysis: { onRetryAnalysis(effectiveIds) },
                onDelete: { onDelete(effectiveIds) }
            )
        }
        .task {
            guard thumbnail == nil else { return }
            await loadThumbnail()
        }
    }

    // MARK: - Glass-aware sub-views

    /// "Analyzing..." shimmer badge with glass on macOS 26+.
    @ViewBuilder
    private var shimmerBadge: some View {
        let base = ShimmerText("Analyzing...")
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

        #if compiler(>=6.3)
        if #available(macOS 26, *) {
            base
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        } else {
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        }
        #else
        base
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .dark)
        #endif
    }

    /// Circular hover-action button icon with a static dark background.
    /// Glass effect was removed because it adapts to the underlying image,
    /// causing a visible dark→transparent shift when the button appears on hover.
    private func hoverButtonIcon(_ systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
    }

    /// Retry analysis badge with red-tinted glass on macOS 26+.
    @ViewBuilder
    private var retryBadge: some View {
        let base = HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.caption2)
            Text("Retry")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)

        #if compiler(>=6.3)
        if #available(macOS 26, *) {
            base.glassEffect(.regular.tint(.red).interactive(), in: .rect(cornerRadius: 6))
        } else {
            base
                .background(.red.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        #else
        base
            .background(.red.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    /// Check if the mouse cursor is currently inside this grid item's frame.
    /// Converts AppKit window coordinates (origin bottom-left) to SwiftUI's
    /// flipped global space (origin top-left of content area).
    private func mouseIsInsideGridItem() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        let mouseLoc = window.mouseLocationOutsideOfEventStream
        let contentRect = window.contentLayoutRect
        let swiftUIPoint = CGPoint(
            x: mouseLoc.x,
            y: contentRect.maxY - mouseLoc.y
        )
        return globalFrame.contains(swiftUIPoint)
    }

    private func loadThumbnail() async {
        if let loaded = await ImageCacheService.shared.loadThumbnail(id: item.id, filename: item.filename) {
            self.thumbnail = loaded
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if reduceMotion {
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(ShimmerConfig.peakBrightness))
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: ShimmerConfig.cycle)
                    / ShimmerConfig.cycle
                let phase = t * (ShimmerConfig.rangeEnd - ShimmerConfig.rangeStart)
                    + ShimmerConfig.rangeStart

                Text(text)
                    .font(.callout)
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
