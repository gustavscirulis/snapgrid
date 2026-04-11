import SwiftUI
import AVKit

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD — Thumbnail → Detail Hero (iOS)
 *
 * OPEN
 *    0ms   thumbnail hidden, backdrop 0 → 1.0
 *          hero image springs from sourceRect → finalFrame
 *
 * SETTLED (after hero completes)
 *          Image centered with faded inline metadata below
 *          Swipe horizontal to navigate, drag down to dismiss
 *          Pinch/double-tap to zoom
 *
 * CLOSE (hero back to grid)
 *    0ms   switch to hero image, backdrop 1.0 → 0
 *          hero springs back to closeTargetFrame
 *  ~360ms  overlay removed
 *
 * CLOSE (slide down, when grid cell not visible)
 *    0ms   slide down + fade
 *  ~250ms  overlay removed
 *
 * METADATA REVEAL
 *    After hero animation completes, metadata section fades in
 *    with staggered timing: title → pills → description → file info.
 *    Metadata is always visible below the image at low opacity.
 * ───────────────────────────────────────────────────────── */

enum MetadataReveal {
    static let titleDelay:       Duration = .milliseconds(100)
    static let pillsDelay:       Duration = .milliseconds(300)
    static let tagStagger:       Double   = 0.05
    static let descriptionDelay: Duration = .milliseconds(450)
    static let fileInfoDelay:    Duration = .milliseconds(600)
    static let slideDistance:    CGFloat  = 8
}

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD — Delete (Wallet Card Crush)
 *
 *    0ms   height clips inward (top + bottom) → 5%, width stays 100%
 *  280ms   width shrinks → 0%, opacity fades → 0
 *  500ms   animation complete, item removed, next image loads
 * ───────────────────────────────────────────────────────── */

private enum DeleteAnimation {
    static let heightCrush = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let widthCrush  = Animation.spring(response: 0.25, dampingFraction: 0.9)
    static let widthDelay: Duration = .milliseconds(280)
    static let completeDelay: Duration = .milliseconds(500)
    static let crushedScaleY: CGFloat = 0.05   // near-zero height slit
    static let crushedScaleX: CGFloat = 0.0     // fully collapsed
}

/// Conditionally applies the delete-animation mask only when active.
/// Skipping `.mask {}` entirely when `deleteStage == 0` avoids an
/// unnecessary offscreen compositing pass on every frame.
private struct DeleteMaskModifier: ViewModifier {
    let deleteStage: Int
    let finalFrame: CGRect
    let zoomScale: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if deleteStage >= 1 {
            content.mask {
                let maskH = finalFrame.height * DeleteAnimation.crushedScaleY
                let maskW = deleteStage >= 2
                    ? finalFrame.width * DeleteAnimation.crushedScaleX
                    : finalFrame.width * zoomScale
                RoundedRectangle(cornerRadius: cornerRadius)
                    .frame(width: maskW, height: maskH)
            }
        } else {
            content
        }
    }
}

// MARK: - Stage Reveal Modifier

extension View {
    func stageReveal(stage: Int, threshold: Int) -> some View {
        self
            .opacity(stage >= threshold ? 1 : 0)
            .offset(y: stage >= threshold ? 0 : 4)
            .animation(SnapSpring.resolvedMetadata, value: stage)
    }

    @ViewBuilder
    func detailScrollTracking(contentOffset: Binding<CGFloat>) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geo in
                max(geo.contentOffset.y, 0)
            } action: { _, newOffset in
                contentOffset.wrappedValue = newOffset
            }
        } else {
            self
        }
    }
}

// MARK: - Full Screen Image Overlay

struct FullScreenImageOverlay: View {
    let startIndex: Int
    let sourceRect: CGRect
    let screenSize: CGSize
    let thumbnailImage: UIImage?
    @Binding var gridItemRects: [String: CGRect]
    let closeRequestID: Int
    let shareRequestID: Int
    let deleteRequestID: Int
    let topReservedInset: CGFloat
    var onCurrentItemChanged: ((String) -> Void)?
    var onHeroSettledChanged: ((Bool) -> Void)?
    var onClose: () -> Void
    var onSearchPattern: ((String) -> Void)?
    var onDelete: ((MediaItem) -> Void)?

    /// Captured at open time — stays stable even when parent re-filters.
    @State private var items: [MediaItem]
    @State private var currentIndex: Int

    // Phase control
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var heroComplete = false
    @State private var hasNavigated = false

    // Content
    @State private var image: UIImage?
    @State private var isLoadingFullRes = false
    @State private var player: AVPlayer?
    @State private var loadTask: Task<Void, Never>?

    // Swipe navigation
    @State private var swipeOffset: CGFloat = 0
    @State private var isNavigating = false
    @State private var adjacentImages: [String: UIImage] = [:]

    // Dismiss gesture
    @State private var dismissOffset: CGFloat = 0

    // Metadata reveal (scroll up to show)
    @State private var contentOffset: CGFloat = 0
    @State private var metadataStage: Int = 0
    @State private var revealTask: Task<Void, Never>?
    @State private var metadataHeight: CGFloat = 0

    // Zoom state (owned here to avoid gesture conflicts with child views)
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomLastScale: CGFloat = 1.0
    @State private var zoomPanOffset: CGSize = .zero
    @State private var zoomPanLastOffset: CGSize = .zero

    // Gesture mode tracking — locked per gesture
    @State private var gestureActive = false
    private enum GestureMode { case none, dismiss, scroll, swipe, zoomPan }
    @State private var gestureMode: GestureMode = .none

    // Delete animation — wallet-style card crush
    // Stage 0: normal, 1: height clips inward, 2: width shrinks + fade, 3: complete
    @State private var deleteStage: Int = 0

    // Share sheet
    @State private var shareItem: URL?

    // Search-triggered close (skips rect correction since grid has re-laid out)
    @State private var isSearchDismiss = false

    // Real-time gesture translation (synchronous updates, no frame delay)
    private struct GestureDrag: Equatable {
        var active: Bool = false
        var translation: CGSize = .zero
    }
    @GestureState private var gestureDrag = GestureDrag()

    // Close target frame (updated reactively from grid rects)
    @State private var closeTargetFrame: CGRect

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 4.0
    private let doubleTapZoomScale: CGFloat = 2.5

    /// Current item derived from index
    private var item: MediaItem { items[currentIndex] }

    private var displayImage: UIImage? { image ?? thumbnailImage }

    private var zoomedCornerRadius: CGFloat { isZoomed ? 0 : 16 }

    init(
        items: [MediaItem],
        startIndex: Int,
        sourceRect: CGRect,
        screenSize: CGSize,
        thumbnailImage: UIImage?,
        gridItemRects: Binding<[String: CGRect]>,
        closeRequestID: Int = 0,
        shareRequestID: Int = 0,
        deleteRequestID: Int = 0,
        topReservedInset: CGFloat = 0,
        onCurrentItemChanged: ((String) -> Void)? = nil,
        onHeroSettledChanged: ((Bool) -> Void)? = nil,
        onClose: @escaping () -> Void,
        onSearchPattern: ((String) -> Void)? = nil,
        onDelete: ((MediaItem) -> Void)? = nil
    ) {
        _items = State(initialValue: items)
        self.startIndex = startIndex
        self.sourceRect = sourceRect
        self.screenSize = screenSize
        self.thumbnailImage = thumbnailImage
        _gridItemRects = gridItemRects
        self.closeRequestID = closeRequestID
        self.shareRequestID = shareRequestID
        self.deleteRequestID = deleteRequestID
        self.topReservedInset = topReservedInset
        self.onCurrentItemChanged = onCurrentItemChanged
        self.onHeroSettledChanged = onHeroSettledChanged
        self.onClose = onClose
        self.onSearchPattern = onSearchPattern
        self.onDelete = onDelete
        _currentIndex = State(initialValue: startIndex)
        _closeTargetFrame = State(initialValue: sourceRect)
    }

    // MARK: - Computed Properties

    // Effective offsets: prefer @GestureState (synchronous) during active gesture,
    // fall back to @State (for animations) when gesture is inactive.

    private var effectiveSwipeOffset: CGFloat {
        if gestureDrag.active && gestureMode == .swipe {
            var proposed = gestureDrag.translation.width
            if (currentIndex == 0 && proposed > 0) ||
               (currentIndex == items.count - 1 && proposed < 0) {
                proposed *= 0.3
            }
            return proposed
        }
        return swipeOffset
    }

    private var effectiveDismissOffset: CGFloat {
        if gestureDrag.active && gestureMode == .dismiss {
            return max(0, gestureDrag.translation.height)
        }
        return dismissOffset
    }

    private var effectiveZoomPanOffset: CGSize {
        if gestureDrag.active && gestureMode == .zoomPan {
            let raw = CGSize(
                width: zoomPanLastOffset.width + gestureDrag.translation.width,
                height: zoomPanLastOffset.height + gestureDrag.translation.height
            )
            return rubberBandZoomPanOffset(raw)
        }
        return zoomPanOffset
    }

    /// Hard clamp — used as the snap-back target on gesture end.
    /// Overload without `finalFrame` recomputes it (convenience for gesture handlers).
    private func clampedZoomPanOffset(_ offset: CGSize) -> CGSize {
        clampedZoomPanOffset(offset, finalFrame: computeFinalFrame(for: item))
    }

    private func clampedZoomPanOffset(_ offset: CGSize, finalFrame: CGRect) -> CGSize {
        guard zoomScale > minZoomScale else { return .zero }
        let screen = CGRect(origin: .zero, size: screenSize)
        let maxOffsetX = max(0, (finalFrame.width * zoomScale - screen.width) / 2)
        let maxOffsetY = max(0, (finalFrame.height * zoomScale - screen.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    /// Rubber-band — allows overstretch with logarithmic resistance during live gesture.
    /// Overload without `finalFrame` recomputes it (convenience for gesture handlers).
    private func rubberBandZoomPanOffset(_ offset: CGSize) -> CGSize {
        rubberBandZoomPanOffset(offset, finalFrame: computeFinalFrame(for: item))
    }

    private func rubberBandZoomPanOffset(_ offset: CGSize, finalFrame: CGRect) -> CGSize {
        guard zoomScale > minZoomScale else { return .zero }
        let screen = CGRect(origin: .zero, size: screenSize)
        let maxOffsetX = max(0, (finalFrame.width * zoomScale - screen.width) / 2)
        let maxOffsetY = max(0, (finalFrame.height * zoomScale - screen.height) / 2)
        return CGSize(
            width: rubberBandAxis(offset.width, limit: maxOffsetX),
            height: rubberBandAxis(offset.height, limit: maxOffsetY)
        )
    }

    /// Applies logarithmic resistance when value exceeds ±limit
    private func rubberBandAxis(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        if value > limit {
            let overshoot = value - limit
            return limit + log2(1 + overshoot / 12) * 12
        } else if value < -limit {
            let overshoot = -value - limit
            return -limit - log2(1 + overshoot / 12) * 12
        }
        return value
    }

    private var backdropOpacity: Double {
        if !isExpanded { return 0 }
        let dragProgress = min(abs(effectiveDismissOffset) / 300.0, 1.0)
        return 1.0 - dragProgress * 0.5
    }

    private var blurOpacity: Double {
        if !isExpanded { return 0 }
        // During active dismiss gesture, hide material blur entirely to avoid
        // per-frame recompositing of the expensive .ultraThinMaterial effect.
        if gestureDrag.active && gestureMode == .dismiss { return 0 }
        let dragProgress = min(abs(effectiveDismissOffset) / 80.0, 1.0)
        return 1.0 - dragProgress
    }

    private var dismissScale: CGFloat {
        let progress = min(abs(effectiveDismissOffset) / 400.0, 1.0)
        return 1.0 - progress * 0.1
    }

    private func computeFinalFrame(for mediaItem: MediaItem) -> CGRect {
        let screen = screenSize
        let maxW = screen.width - 24  // 12pt padding on each side
        let bottomReservedInset: CGFloat = 88
        let availableHeight = max(screen.height - topReservedInset - bottomReservedInset, 1)
        let maxH = min(screen.height * 0.85, availableHeight)
        let itemW = max(CGFloat(mediaItem.width), 1)
        let itemH = max(CGFloat(mediaItem.height), 1)
        let widthScale = maxW / itemW
        let heightScale = maxH / itemH
        let scale = min(widthScale, heightScale)
        let w = itemW * scale
        let h = itemH * scale
        return CGRect(
            x: (screen.width - w) / 2,
            y: topReservedInset + ((availableHeight - h) / 2),
            width: w,
            height: h
        )
    }

    // MARK: - Body

    var body: some View {
        let finalFrame = computeFinalFrame(for: item)

        ZStack {
            // 1. Backdrop — keep the underlying screen visible through blur.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .opacity(blurOpacity)
                Color.black.opacity(0.3)
                    .opacity(backdropOpacity)
            }
            .ignoresSafeArea()

            // 2. Adjacent images — only after hero, hidden during close
            if heroComplete && !isClosing {
                if currentIndex > 0 {
                    adjacentItemView(for: items[currentIndex - 1])
                        .offset(x: -screenSize.width + effectiveSwipeOffset)
                }
                if currentIndex < items.count - 1 {
                    adjacentItemView(for: items[currentIndex + 1])
                        .offset(x: screenSize.width + effectiveSwipeOffset)
                }
            }

            // 3. Current content — hero image OR settled ScrollView
            if heroComplete && !isClosing {
                settledContentView(finalFrame: finalFrame)
                    .offset(x: effectiveSwipeOffset)
            } else {
                heroImage(finalFrame: finalFrame)
            }

        }
        .ignoresSafeArea()
        .onAppear {
            impactFeedback.prepare()
            loadFullImage()
            prepareVideoIfNeeded()
            preloadAdjacentImages()
            onCurrentItemChanged?(item.id)
            withAnimation(SnapSpring.resolvedHero) {
                isExpanded = true
            } completion: {
                heroComplete = true
                onHeroSettledChanged?(true)
                startMetadataReveal()
            }
        }
        .onChange(of: closeRequestID) { oldValue, newValue in
            guard newValue != oldValue, !isClosing else { return }
            close()
        }
        .onChange(of: shareRequestID) { oldValue, newValue in
            guard newValue != oldValue else { return }
            prepareShareItem()
        }
        .onChange(of: deleteRequestID) { oldValue, newValue in
            guard newValue != oldValue, deleteStage == 0, !isClosing else { return }
            handleDelete()
        }
    }

    // MARK: - Hero Image (Phase A/C)

    @ViewBuilder
    private func heroImage(finalFrame: CGRect) -> some View {
        let currentFrame = isExpanded ? finalFrame : closeTargetFrame
        let cornerRadius: CGFloat = isExpanded ? 16 : 12

        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: currentFrame.width, height: currentFrame.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: currentFrame.width, height: currentFrame.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .position(x: currentFrame.midX, y: currentFrame.midY + dismissOffset)
    }

    // MARK: - Settled Content View (Phase B)

    @ViewBuilder
    private func settledContentView(finalFrame: CGRect) -> some View {
        let screen = CGRect(origin: .zero, size: screenSize)
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: finalFrame.minY)

                ZStack {
                    Group {
                        if item.isVideo, let player {
                            VideoPlayer(player: player)
                                .frame(width: finalFrame.width * zoomScale, height: finalFrame.height * zoomScale)
                        } else if let displayImage {
                            Image(uiImage: displayImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: finalFrame.width * zoomScale, height: finalFrame.height * zoomScale)
                                .clipped()
                                .drawingGroup(opaque: false)
                        } else {
                            Rectangle()
                                .fill(Color.snapDarkMuted)
                                .frame(width: finalFrame.width, height: finalFrame.height)
                                .overlay {
                                    ProgressView()
                                        .tint(.white.opacity(0.3))
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: zoomedCornerRadius))
                    .modifier(DeleteMaskModifier(
                        deleteStage: deleteStage,
                        finalFrame: finalFrame,
                        zoomScale: zoomScale,
                        cornerRadius: zoomedCornerRadius
                    ))
                    .offset(effectiveZoomPanOffset)
                    .opacity(deleteStage >= 2 ? 0 : 1)
                }
                .frame(width: screen.width, height: finalFrame.height)

                DetailMetadataSection(item: item, stage: metadataStage) { pattern in
                    searchAndClose(pattern: pattern)
                }
                .id(item.id)
                .frame(width: screen.width)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MetadataHeightKey.self, value: proxy.size.height)
                    }
                )
                .padding(.top, 32)
                .padding(.bottom, 120)
                .opacity(deleteStage >= 1 ? 0 : (isZoomed ? 0 : metadataOpacity))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDisabled(isZoomed)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.top)
        .detailScrollTracking(contentOffset: $contentOffset)
        .contentShape(Rectangle())
        .simultaneousGesture(settledDragGesture)
        .simultaneousGesture(pinchGesture)
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    handleDoubleTap(at: value.location)
                }
        )
        .onPreferenceChange(MetadataHeightKey.self) { newHeight in
            // Skip preference updates during dismiss to avoid extra layout passes
            guard !(gestureDrag.active && gestureMode == .dismiss) else { return }
            metadataHeight = newHeight
        }
        .sheet(isPresented: Binding(
            get: { shareItem != nil },
            set: { if !$0 { shareItem = nil } }
        )) {
            if let url = shareItem {
                ActivityView(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        // Dismiss visual effects
        .offset(y: effectiveDismissOffset)
        .scaleEffect(effectiveDismissOffset > 0 ? dismissScale : 1.0)
    }

    /// Copy file to temp directory so share sheet shows "Send a Copy" only (no iCloud collaboration).
    private func prepareShareItem() {
        guard let url = item.mediaURL else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            shareItem = tempURL
        } catch {
            // Fallback to original URL if copy fails
            shareItem = url
        }
    }

    // MARK: - Adjacent Item View

    @ViewBuilder
    private func adjacentItemView(for adjacentItem: MediaItem) -> some View {
        let frame = computeFinalFrame(for: adjacentItem)
        let adjImage = adjacentImages[adjacentItem.id]

        if let adjImage {
            Image(uiImage: adjImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .position(x: frame.midX, y: frame.midY)
        } else if let thumbURL = adjacentItem.thumbnailURL,
                  let cached = ThumbnailCache.shared.image(for: thumbURL) {
            Image(uiImage: cached)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .position(x: frame.midX, y: frame.midY)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.snapDarkMuted)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    /// Metadata starts very faded, becomes readable as user scrolls up
    private var metadataOpacity: Double {
        let base = 0.15
        let progress = min(contentOffset / 80, 1.0)
        return base + (1.0 - base) * progress
    }

    // MARK: - Metadata Reveal

    private func startMetadataReveal() {
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: MetadataReveal.titleDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 1 }

            try? await Task.sleep(for: MetadataReveal.pillsDelay - MetadataReveal.titleDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 2 }

            try? await Task.sleep(for: MetadataReveal.descriptionDelay - MetadataReveal.pillsDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 3 }

            try? await Task.sleep(for: MetadataReveal.fileInfoDelay - MetadataReveal.descriptionDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 4 }
        }
    }

    // MARK: - Settled Drag Gesture

    private var settledDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($gestureDrag) { value, state, _ in
                state = GestureDrag(active: true, translation: value.translation)
            }
            .onChanged { value in
                // Only lock gesture mode on first event. No @State offset
                // mutations here — the view reads @GestureState via effective*
                // computed properties. Mutating @State would schedule a second
                // (redundant) render that fights with the synchronous one.
                guard !gestureActive else { return }
                gestureActive = true

                let tx = value.translation.width
                let ty = value.translation.height

                if isZoomed {
                    gestureMode = .zoomPan
                    zoomPanLastOffset = zoomPanOffset
                } else if abs(tx) > abs(ty) + 4 {
                    gestureMode = .swipe
                } else if ty > 0 && contentOffset <= 0.5 {
                    gestureMode = .dismiss
                } else {
                    gestureMode = .none
                }
            }
            .onEnded { value in
                let mode = gestureMode
                let tx = value.translation.width
                let ty = value.translation.height

                // Sync @State to final gesture position. This provides
                // the starting point for end-of-gesture animations and
                // the fallback value when @GestureState resets.
                switch mode {
                case .zoomPan:
                    // Store the raw (possibly overstretched) offset so @GestureState
                    // reset doesn't jump — the spring animation below snaps it back.
                    let raw = CGSize(
                        width: zoomPanLastOffset.width + tx,
                        height: zoomPanLastOffset.height + ty
                    )
                    zoomPanOffset = rubberBandZoomPanOffset(raw)
                case .swipe:
                    var proposed = tx
                    if (currentIndex == 0 && proposed > 0) ||
                       (currentIndex == items.count - 1 && proposed < 0) {
                        proposed *= 0.3
                    }
                    swipeOffset = proposed
                case .dismiss:
                    dismissOffset = max(0, ty)
                case .scroll:
                    break
                case .none: break
                }

                gestureActive = false
                gestureMode = .none

                // Now handle end-of-gesture animations / navigation
                switch mode {
                case .zoomPan:
                    // Spring back to clamped bounds if overstretched
                    let snapped = clampedZoomPanOffset(zoomPanOffset)
                    if snapped != zoomPanOffset {
                        withAnimation(SnapSpring.resolvedStandard) {
                            zoomPanOffset = snapped
                        }
                    }
                    zoomPanLastOffset = snapped

                case .swipe:
                    let velocity = value.predictedEndTranslation.width - tx
                    let threshold = screenSize.width * 0.3
                    let velocityThreshold: CGFloat = 200

                    var newIndex = currentIndex
                    if swipeOffset < -threshold || velocity < -velocityThreshold {
                        newIndex = min(currentIndex + 1, items.count - 1)
                    } else if swipeOffset > threshold || velocity > velocityThreshold {
                        newIndex = max(currentIndex - 1, 0)
                    }

                    if newIndex != currentIndex {
                        navigateTo(newIndex)
                    } else {
                        withAnimation(SnapSpring.resolvedStandard) {
                            swipeOffset = 0
                        }
                    }

                case .dismiss:
                    if dismissOffset > 100 || value.predictedEndTranslation.height > 300 {
                        close()
                    } else {
                        withAnimation(SnapSpring.resolvedStandard) {
                            dismissOffset = 0
                        }
                    }

                case .scroll:
                    break

                case .none:
                    break
                }
            }
    }

    // MARK: - Pinch-to-Zoom Gesture

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = zoomLastScale * value.magnification
                let prevZoom = zoomScale
                let newZoom = rubberBand(raw, min: minZoomScale, max: maxZoomScale)

                // Focal-point zoom: adjust pan so the pinch center stays fixed.
                // Convert startAnchor (UnitPoint 0–1) to screen coordinates.
                if prevZoom > 0 && newZoom != prevZoom {
                    let screen = UIScreen.main.bounds
                    let anchor = CGPoint(
                        x: value.startAnchor.x * screen.width,
                        y: value.startAnchor.y * screen.height
                    )
                    let finalFrame = computeFinalFrame(for: item)
                    let currentOffset = effectiveZoomPanOffset
                    let imageCenterX = finalFrame.midX + currentOffset.width
                    let imageCenterY = finalFrame.midY + currentOffset.height
                    let ratio = newZoom / prevZoom
                    let dx = -(anchor.x - imageCenterX) * (ratio - 1)
                    let dy = -(anchor.y - imageCenterY) * (ratio - 1)
                    zoomPanOffset.width += dx
                    zoomPanOffset.height += dy
                    zoomPanLastOffset.width += dx
                    zoomPanLastOffset.height += dy
                }

                zoomScale = newZoom
                let wasZoomed = isZoomed
                isZoomed = zoomScale > minZoomScale
                if isZoomed && !wasZoomed {
                    // Upgrade simultaneous drag to zoomPan so two-finger
                    // panning works during the same gesture that started the zoom.
                    if gestureActive && gestureMode != .zoomPan {
                        gestureMode = .zoomPan
                        // Subtract accumulated translation for a seamless handoff
                        zoomPanLastOffset = CGSize(
                            width: zoomPanOffset.width - gestureDrag.translation.width,
                            height: zoomPanOffset.height - gestureDrag.translation.height
                        )
                        dismissOffset = 0
                    }
                }
            }
            .onEnded { _ in
                let clamped = min(max(zoomScale, minZoomScale), maxZoomScale)
                withAnimation(SnapSpring.resolvedStandard) {
                    zoomScale = clamped
                    if clamped <= minZoomScale {
                        zoomPanOffset = .zero
                    } else {
                        zoomPanOffset = clampedZoomPanOffset(zoomPanOffset)
                    }
                }
                zoomLastScale = clamped
                isZoomed = clamped > minZoomScale
            }
    }

    // MARK: - Double-Tap to Zoom

    private func handleDoubleTap(at location: CGPoint) {
        let viewCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        withAnimation(SnapSpring.resolvedStandard) {
            if zoomScale > minZoomScale {
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                isZoomed = false
            } else {
                zoomScale = doubleTapZoomScale
                zoomLastScale = doubleTapZoomScale
                let rawOffset = CGSize(
                    width: (viewCenter.x - location.x) * (doubleTapZoomScale - 1),
                    height: (viewCenter.y - location.y) * (doubleTapZoomScale - 1)
                )
                zoomPanOffset = clampedZoomPanOffset(rawOffset)
                isZoomed = true
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rubberBand(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        if value < minVal {
            let overshoot = minVal - value
            return minVal - log2(1 + overshoot) * 0.15
        } else if value > maxVal {
            let overshoot = value - maxVal
            return maxVal + log2(1 + overshoot) * 0.15
        }
        return value
    }

    // MARK: - Navigation

    private func navigateTo(_ newIndex: Int) {
        guard newIndex >= 0, newIndex < items.count,
              newIndex != currentIndex, !isNavigating, !isClosing else {
            withAnimation(SnapSpring.resolvedStandard) { swipeOffset = 0 }
            return
        }
        isNavigating = true
        let direction: CGFloat = newIndex > currentIndex ? -1 : 1

        player?.pause()
        player = nil
        impactFeedback.impactOccurred()

        withAnimation(SnapSpring.resolvedStandard) {
            swipeOffset = direction * screenSize.width
        } completion: {
            // Swap without animation
            let t = Transaction(animation: nil)
            withTransaction(t) {
                currentIndex = newIndex
                hasNavigated = true
                swipeOffset = 0
                metadataStage = 4
                contentOffset = 0
                isZoomed = false
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                zoomPanLastOffset = .zero
                image = adjacentImages[items[newIndex].id]
            }

            onCurrentItemChanged?(items[newIndex].id)

            revealTask?.cancel()

            loadTask?.cancel()
            loadTask = Task {
                await loadCurrentItem()
            }
            preloadAdjacentImages()
            isNavigating = false
        }
    }

    // MARK: - Search & Close

    private func searchAndClose(pattern: String) {
        guard !isClosing else { return }
        isSearchDismiss = true
        onSearchPattern?(pattern)

        // Wait for the grid to re-filter and report the current item's
        // updated rect on the visible screen.  The search debounce is 100ms,
        // then SwiftUI needs 1-2 render cycles for layout + preference
        // propagation.  Poll at short intervals instead of a fixed delay
        // so we close as soon as the rect is ready.
        let targetId = items[currentIndex].id
        let screen = UIScreen.main.bounds
        Task { @MainActor in
            for _ in 0..<20 { // 20 × 30ms = 600ms max
                try? await Task.sleep(for: .milliseconds(30))
                if let rect = gridItemRects[targetId],
                   screen.intersects(rect) {
                    break
                }
            }
            close()
        }
    }

    // MARK: - Delete

    private func handleDelete() {
        // Reset zoom before delete animation so mask dimensions are correct
        if isZoomed {
            withAnimation(SnapSpring.resolvedFast) {
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                zoomPanLastOffset = .zero
                isZoomed = false
            }
        }

        let deletedIndex = currentIndex
        let deletedItem = items[deletedIndex]
        let isLastItem = deletedIndex == items.count - 1

        // Stage 1 — height crushes inward
        withAnimation(DeleteAnimation.heightCrush) {
            deleteStage = 1
        }

        Task { @MainActor in
            // Stage 2 — width collapses + fade out
            try? await Task.sleep(for: DeleteAnimation.widthDelay)
            withAnimation(DeleteAnimation.widthCrush) {
                deleteStage = 2
            }

            // Stage 3 — crush complete, commit deletion + slide in replacement
            try? await Task.sleep(for: DeleteAnimation.completeDelay)

            // Notify parent to handle file move + SwiftData deletion
            onDelete?(deletedItem)

            // Update local items array
            items.remove(at: deletedIndex)

            if items.isEmpty {
                close()
                return
            }

            // Adjust index
            if deletedIndex >= items.count {
                currentIndex = items.count - 1
            }

            onCurrentItemChanged?(items[currentIndex].id)

            // Prepare new image before resetting delete state
            player?.pause()
            player = nil
            image = adjacentImages[items[currentIndex].id]
            contentOffset = 0

            // Position replacement off-screen: from right normally, from left if last
            let slideFrom = isLastItem ? -screenSize.width : screenSize.width
            swipeOffset = slideFrom
            deleteStage = 0
            metadataStage = 0

            // Animate the slide-in
            withAnimation(SnapSpring.resolvedStandard) {
                swipeOffset = 0
            }

            // Stagger metadata reveal after slide settles
            try? await Task.sleep(for: .milliseconds(200))
            startMetadataReveal()

            loadTask?.cancel()
            loadTask = Task { await loadCurrentItem() }
            preloadAdjacentImages()

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Close

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        heroComplete = false
        onHeroSettledChanged?(false)
        metadataStage = 0
        revealTask?.cancel()
        contentOffset = 0
        player?.pause()
        impactFeedback.impactOccurred()

        // Reset zoom instantly
        zoomScale = minZoomScale
        zoomLastScale = minZoomScale
        zoomPanOffset = .zero
        zoomPanLastOffset = .zero
        isZoomed = false

        let currentItemId = items[currentIndex].id
        onCurrentItemChanged?(currentItemId)
        let rawRect = gridItemRects[currentItemId]

        // For search dismiss, only accept rects on the visible screen.
        // Preference rects from non-visible space pages can have off-screen
        // coordinates that would send the hero animation out of view.
        let targetRect: CGRect? = if isSearchDismiss {
            rawRect.flatMap { UIScreen.main.bounds.intersects($0) ? $0 : nil }
        } else {
            rawRect
        }

        if let targetRect {
            // Grid cell is visible — hero animation back to it
            var correctedRect = targetRect
            if !isSearchDismiss {
                // Apply correction: sourceRect is ground truth for the original item.
                // Preference-based rects may have a systematic offset (e.g. from
                // off-screen TabView pages), so anchor to sourceRect.
                // Skip this after search-triggered close — grid has re-laid out
                // with new items, so the original correction is invalid.
                let originalItemId = items[startIndex].id
                if let originalGridRect = gridItemRects[originalItemId] {
                    let xCorrection = sourceRect.midX - originalGridRect.midX
                    let yCorrection = sourceRect.midY - originalGridRect.midY
                    correctedRect = CGRect(
                        x: targetRect.origin.x + xCorrection,
                        y: targetRect.origin.y + yCorrection,
                        width: targetRect.width,
                        height: targetRect.height
                    )
                }
            }

            closeTargetFrame = correctedRect

            withAnimation(SnapSpring.resolvedHero) {
                isExpanded = false
                dismissOffset = 0
            } completion: {
                onClose()
            }
        } else {
            // Grid cell not visible — slide down and fade
            withAnimation(.easeOut(duration: 0.25)) {
                dismissOffset = screenSize.height
                isExpanded = false
            } completion: {
                onClose()
            }
        }
    }

    // MARK: - Image Loading

    private func loadFullImage() {
        guard let url = item.mediaURL, !item.isVideo else {
            isLoadingFullRes = false
            return
        }
        isLoadingFullRes = true
        loadTask = Task {
            let loaded = await ThumbnailCache.shared.loadImage(for: url).image
            if !Task.isCancelled {
                image = loaded
                isLoadingFullRes = false
            }
        }
    }

    private func loadCurrentItem() async {
        let currentItem = item

        if currentItem.isVideo {
            prepareVideoIfNeeded()
        } else {
            guard let url = currentItem.mediaURL else {
                isLoadingFullRes = false
                return
            }
            isLoadingFullRes = true
            let loaded = await ThumbnailCache.shared.loadImage(for: url).image
            if !Task.isCancelled {
                image = loaded
                isLoadingFullRes = false
            }
        }
    }

    private func prepareVideoIfNeeded() {
        guard item.isVideo, let url = item.mediaURL else { return }
        Task {
            let monitor = iCloudDownloadMonitor.shared
            if !monitor.isDownloaded(url) {
                await monitor.waitForDownload(of: url, timeout: 60)
            }
            let newPlayer = AVPlayer(url: url)
            self.player = newPlayer
            newPlayer.play()
        }
    }

    // MARK: - Adjacent Images

    private func preloadAdjacentImages() {
        var keepIds: Set<String> = [item.id]
        if currentIndex > 0 { keepIds.insert(items[currentIndex - 1].id) }
        if currentIndex < items.count - 1 { keepIds.insert(items[currentIndex + 1].id) }
        for key in adjacentImages.keys where !keepIds.contains(key) {
            adjacentImages.removeValue(forKey: key)
        }

        for offset in [-1, 1] {
            let idx = currentIndex + offset
            guard idx >= 0, idx < items.count else { continue }
            let adjItem = items[idx]
            if adjacentImages[adjItem.id] != nil { continue }

            if let url = adjItem.mediaURL ?? adjItem.thumbnailURL {
                Task {
                    if let img = await ThumbnailCache.shared.loadImage(for: url).image {
                        adjacentImages[adjItem.id] = img
                    }
                }
            }
        }
    }
}

// MARK: - Metadata Height Preference Key

private struct MetadataHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
