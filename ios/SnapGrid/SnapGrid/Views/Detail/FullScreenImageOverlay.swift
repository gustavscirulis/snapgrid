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
 *          ScrollView with image + staggered metadata reveal
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
 *    Scrolling down reveals metadata with a fade mask.
 * ───────────────────────────────────────────────────────── */

private enum MetadataReveal {
    static let titleDelay:       Duration = .milliseconds(100)
    static let pillsDelay:       Duration = .milliseconds(300)
    static let tagStagger:       Double   = 0.05
    static let descriptionDelay: Duration = .milliseconds(450)
    static let fileInfoDelay:    Duration = .milliseconds(600)
    static let slideDistance:    CGFloat  = 8
    static let spring = SnapSpring.metadata
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

// MARK: - Scroll Offset Tracking (iOS 17)

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Stage Reveal Modifier

private extension View {
    func stageReveal(stage: Int, threshold: Int) -> some View {
        self
            .opacity(stage >= threshold ? 1 : 0)
            .offset(y: stage >= threshold ? 0 : 4)
            .animation(MetadataReveal.spring, value: stage)
    }
}

// MARK: - Full Screen Image Overlay

struct FullScreenImageOverlay: View {
    let startIndex: Int
    let sourceRect: CGRect
    let screenSize: CGSize
    let thumbnailImage: UIImage?
    @Binding var gridItemRects: [String: CGRect]
    var onDismissing: ((String) -> Void)?
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

    // Metadata reveal (manual scroll)
    @State private var contentOffset: CGFloat = 0
    @State private var contentOffsetAtGestureStart: CGFloat = 0
    @State private var metadataStage: Int = 0
    @State private var revealTask: Task<Void, Never>?
    @State private var isDescriptionExpanded = false
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

    // Delete confirmation
    @State private var showDeleteConfirmation = false

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

    init(
        items: [MediaItem],
        startIndex: Int,
        sourceRect: CGRect,
        screenSize: CGSize,
        thumbnailImage: UIImage?,
        gridItemRects: Binding<[String: CGRect]>,
        onDismissing: ((String) -> Void)? = nil,
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
        self.onDismissing = onDismissing
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

    private var effectiveContentOffset: CGFloat {
        if gestureDrag.active && gestureMode == .scroll {
            let proposed = contentOffsetAtGestureStart - gestureDrag.translation.height
            if proposed < 0 {
                // Rubber band past top — allows bouncy feel when scrolling back to image
                let overshoot = -proposed
                return -(log2(1 + overshoot) * 8)
            }
            if proposed > maxContentOffset {
                let overshoot = proposed - maxContentOffset
                return maxContentOffset + log2(1 + overshoot) * 8
            }
            return proposed
        }
        return contentOffset
    }

    private var effectiveZoomPanOffset: CGSize {
        if gestureDrag.active && gestureMode == .zoomPan {
            return CGSize(
                width: zoomPanLastOffset.width + gestureDrag.translation.width,
                height: zoomPanLastOffset.height + gestureDrag.translation.height
            )
        }
        return zoomPanOffset
    }

    private var backdropOpacity: Double {
        if !isExpanded { return 0 }
        let dragProgress = min(abs(effectiveDismissOffset) / 300.0, 1.0)
        return 1.0 - dragProgress * 0.5
    }

    private var dismissScale: CGFloat {
        let progress = min(abs(effectiveDismissOffset) / 400.0, 1.0)
        return 1.0 - progress * 0.1
    }

    private func computeFinalFrame(for mediaItem: MediaItem) -> CGRect {
        // Use actual screen bounds for true centering (screenSize from GeometryReader
        // excludes safe area, but the overlay ignores safe area)
        let screen = UIScreen.main.bounds.size
        let maxW = screen.width - 24  // 12pt padding on each side
        let maxH = screen.height * 0.85
        let widthScale = maxW / CGFloat(mediaItem.width)
        let heightScale = maxH / CGFloat(mediaItem.height)
        let scale = min(widthScale, heightScale)
        let w = CGFloat(mediaItem.width) * scale
        let h = CGFloat(mediaItem.height) * scale
        return CGRect(
            x: (screen.width - w) / 2,
            y: (screen.height - h) / 2,
            width: w,
            height: h
        )
    }

    // MARK: - Body

    var body: some View {
        let finalFrame = computeFinalFrame(for: item)

        ZStack {
            // 1. Backdrop — material blur + tint (matches Mac app)
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .opacity(backdropOpacity)
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
            withAnimation(SnapSpring.hero) {
                isExpanded = true
            } completion: {
                heroComplete = true
                startMetadataReveal()
            }
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
        let screen = UIScreen.main.bounds
        // Metadata top starts near screen bottom — ~50pt peeks initially
        let metadataTopY = screen.height - 50

        ZStack {
            // Image — centered at finalFrame, scrolls up with content
            Group {
                if item.isVideo, let player {
                    VideoPlayer(player: player)
                        .frame(width: finalFrame.width, height: finalFrame.height)
                } else if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: finalFrame.width, height: finalFrame.height)
                        .clipped()
                        .scaleEffect(zoomScale)
                        .offset(effectiveZoomPanOffset)
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
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // Delete animation — wallet card crush (mask approach)
            .mask {
                let maskH = deleteStage >= 1
                    ? finalFrame.height * DeleteAnimation.crushedScaleY
                    : finalFrame.height
                let maskW = deleteStage >= 2
                    ? finalFrame.width * DeleteAnimation.crushedScaleX
                    : finalFrame.width
                RoundedRectangle(cornerRadius: 16)
                    .frame(width: maskW, height: maskH)
            }
            .opacity(deleteStage >= 2 ? 0 : 1)
            .position(x: finalFrame.midX, y: finalFrame.midY)
            .offset(y: -effectiveContentOffset)

            // Metadata — positioned so top starts near screen bottom (peek)
            DetailMetadataSection(item: item, stage: metadataStage, isDescriptionExpanded: $isDescriptionExpanded) { pattern in
                searchAndClose(pattern: pattern)
            }
                .id(item.id)
                .frame(width: max(min(finalFrame.width, screen.width - 32), 300))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MetadataHeightKey.self, value: proxy.size.height)
                    }
                )
                .offset(y: metadataTopY - effectiveContentOffset)
                .opacity(deleteStage >= 1 ? 0 : metadataOpacity)

            // Action toolbar — share + delete (Glass split button)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    actionToolbar
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
                .opacity(!isZoomed && contentOffset < 80 && deleteStage == 0 ? 1 : 0)
                .animation(SnapSpring.fast, value: isZoomed)
                .animation(SnapSpring.fast, value: contentOffset < 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Rasterize content so swipe/dismiss transforms are pure GPU operations.
        // During swipe/dismiss the inner content is static (only outer offset changes),
        // so the texture is reused — no per-frame blur recomputation.
        .drawingGroup()
        .contentShape(Rectangle())
        .gesture(settledDragGesture)
        .simultaneousGesture(pinchGesture)
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    handleDoubleTap(at: value.location)
                }
        )
        .onPreferenceChange(MetadataHeightKey.self) { metadataHeight = $0 }
        .onChange(of: metadataHeight) { oldHeight, newHeight in
            // When metadata grows while scrolled (e.g. description expanded), scroll to reveal
            if contentOffset > 0 && newHeight > oldHeight {
                withAnimation(MetadataReveal.spring) {
                    contentOffset = maxContentOffset
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                handleDelete()
            }
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

    // MARK: - Action Toolbar (Glass split button)

    @ViewBuilder
    private var actionToolbar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        prepareShareItem()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 56, height: 50)
                    }

                    Divider()
                        .frame(height: 24)
                        .opacity(0.3)

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 56, height: 50)
                    }
                }
                .glassEffect(.regular.interactive())
            }
        } else {
            HStack(spacing: 0) {
                Button {
                    prepareShareItem()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 56, height: 50)
                }

                Divider()
                    .frame(height: 24)
                    .opacity(0.3)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 56, height: 50)
                }
            }
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
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

    // MARK: - Metadata Fade Mask

    /// How far the user can scroll up to reveal metadata
    private var maxContentOffset: CGFloat {
        let screen = UIScreen.main.bounds
        // Metadata starts 50pt from screen bottom; allow scrolling enough to reveal it all
        let neededForMetadata = metadataHeight - 30
        return max(screen.height * 0.25, neededForMetadata)
    }

    /// Metadata starts faded (0.3), reaches full opacity over 60pt of scroll
    private var metadataOpacity: Double {
        let base = 0.3
        let progress = min(effectiveContentOffset / 60, 1.0)
        return base + (1.0 - base) * progress
    }

    // MARK: - Metadata Reveal

    private func startMetadataReveal() {
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: MetadataReveal.titleDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 1 }

            try? await Task.sleep(for: MetadataReveal.pillsDelay - MetadataReveal.titleDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 2 }

            try? await Task.sleep(for: MetadataReveal.descriptionDelay - MetadataReveal.pillsDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 3 }

            try? await Task.sleep(for: MetadataReveal.fileInfoDelay - MetadataReveal.descriptionDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 4 }
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
                } else if contentOffset > 0 {
                    gestureMode = .scroll
                    contentOffsetAtGestureStart = contentOffset
                } else if abs(tx) > abs(ty) + 4 {
                    gestureMode = .swipe
                } else if ty > 0 {
                    gestureMode = .dismiss
                } else {
                    gestureMode = .scroll
                    contentOffsetAtGestureStart = contentOffset
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
                    zoomPanOffset = CGSize(
                        width: zoomPanLastOffset.width + tx,
                        height: zoomPanLastOffset.height + ty
                    )
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
                    let proposed = contentOffsetAtGestureStart - ty
                    if proposed < 0 {
                        let overshoot = -proposed
                        contentOffset = -(log2(1 + overshoot) * 8)
                    } else if proposed > maxContentOffset {
                        let overshoot = proposed - maxContentOffset
                        contentOffset = maxContentOffset + log2(1 + overshoot) * 8
                    } else {
                        contentOffset = proposed
                    }
                case .none: break
                }

                gestureActive = false
                gestureMode = .none

                // Now handle end-of-gesture animations / navigation
                switch mode {
                case .zoomPan:
                    zoomPanLastOffset = zoomPanOffset

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
                        withAnimation(SnapSpring.standard) {
                            swipeOffset = 0
                        }
                    }

                case .dismiss:
                    if dismissOffset > 100 || value.predictedEndTranslation.height > 300 {
                        close()
                    } else {
                        withAnimation(SnapSpring.standard) {
                            dismissOffset = 0
                        }
                    }

                case .scroll:
                    let velocity = -(value.predictedEndTranslation.height - ty)
                    let projected = contentOffset + velocity * 0.3
                    let snapTarget: CGFloat
                    if projected > maxContentOffset * 0.35 {
                        snapTarget = maxContentOffset
                    } else {
                        snapTarget = 0
                    }
                    withAnimation(SnapSpring.standard) {
                        contentOffset = snapTarget
                    }
                    contentOffsetAtGestureStart = snapTarget

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
                zoomScale = rubberBand(raw, min: minZoomScale, max: maxZoomScale)
                isZoomed = zoomScale > minZoomScale
            }
            .onEnded { _ in
                let clamped = min(max(zoomScale, minZoomScale), maxZoomScale)
                withAnimation(SnapSpring.standard) {
                    zoomScale = clamped
                    if clamped <= minZoomScale {
                        zoomPanOffset = .zero
                    }
                }
                zoomLastScale = clamped
                isZoomed = clamped > minZoomScale
            }
    }

    // MARK: - Double-Tap to Zoom

    private func handleDoubleTap(at location: CGPoint) {
        let viewCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        withAnimation(SnapSpring.standard) {
            if zoomScale > minZoomScale {
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                isZoomed = false
            } else {
                zoomScale = doubleTapZoomScale
                zoomLastScale = doubleTapZoomScale
                zoomPanOffset = CGSize(
                    width: (viewCenter.x - location.x) * (doubleTapZoomScale - 1),
                    height: (viewCenter.y - location.y) * (doubleTapZoomScale - 1)
                )
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
            withAnimation(SnapSpring.standard) { swipeOffset = 0 }
            return
        }
        isNavigating = true
        let direction: CGFloat = newIndex > currentIndex ? -1 : 1

        player?.pause()
        player = nil
        impactFeedback.impactOccurred()

        withAnimation(SnapSpring.standard) {
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
                isDescriptionExpanded = false
                isZoomed = false
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                zoomPanLastOffset = .zero
                image = adjacentImages[items[newIndex].id]
            }

            onDismissing?(items[newIndex].id)

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
        // Wait for grid to re-filter and re-layout, then close to new position
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            close()
        }
    }

    // MARK: - Delete

    private func handleDelete() {
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
            withAnimation(SnapSpring.standard) {
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
        let targetRect = gridItemRects[currentItemId]

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

            onDismissing?(currentItemId)
            closeTargetFrame = correctedRect

            withAnimation(SnapSpring.hero) {
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

// MARK: - Detail Metadata Section

private struct DetailMetadataSection: View {
    let item: MediaItem
    let stage: Int
    @Binding var isDescriptionExpanded: Bool
    var onSearchPattern: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Analyzing...")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if item.analysisError != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.8))
                    Text("Analysis failed")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if let result = item.analysisResult {
                if !result.imageSummary.isEmpty {
                    Text(result.imageSummary)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .stageReveal(stage: stage, threshold: 1)
                        .padding(.bottom, 12)
                }

                if !result.patterns.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(result.patterns.enumerated()), id: \.element.name) { index, pattern in
                            Text(pattern.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .environment(\.colorScheme, .dark)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSearchPattern?(pattern.name)
                                }
                                .opacity(stage >= 2 ? 1 : 0)
                                .offset(y: stage >= 2 ? 0 : MetadataReveal.slideDistance)
                                .animation(
                                    MetadataReveal.spring.delay(Double(index) * MetadataReveal.tagStagger),
                                    value: stage
                                )
                        }
                    }
                    .padding(.bottom, 14)
                }

                if hasDescription(result) {
                    ExpandableText(
                        text: result.imageContext,
                        lineLimit: 3,
                        font: .system(size: 14),
                        platformFont: .systemFont(ofSize: 14),
                        lineSpacing: 3,
                        textColor: .white.opacity(0.5),
                        animation: MetadataReveal.spring,
                        isExpanded: $isDescriptionExpanded
                    )
                    .opacity(stage >= 3 ? 1 : 0)
                    .animation(MetadataReveal.spring, value: stage)
                }
            }

            HStack(spacing: 0) {
                Text("\(item.width) \u{00D7} \(item.height)")
                Text("  \u{00B7}  ")
                    .foregroundStyle(.white.opacity(0.15))
                Text(item.createdAt, style: .date)
                if let duration = item.duration {
                    Text("  \u{00B7}  ")
                        .foregroundStyle(.white.opacity(0.15))
                    Text(formatDuration(duration))
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
            .stageReveal(stage: stage, threshold: 4)
            .padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .animation(MetadataReveal.spring, value: isDescriptionExpanded)
    }

    private func hasDescription(_ result: AnalysisResult) -> Bool {
        !result.imageContext.isEmpty && result.imageContext != result.imageSummary
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - Metadata Height Preference Key

private struct MetadataHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Expandable Text

/// Truncates to N lines with inline "…" at the exact word boundary.
/// Expands/collapses with a smooth height-clip animation (no text reflow).
private struct ExpandableText: View {
    let text: String
    let lineLimit: Int
    let font: Font
    let platformFont: UIFont
    let lineSpacing: CGFloat
    let textColor: Color
    let animation: Animation
    @Binding var isExpanded: Bool

    @State private var availableWidth: CGFloat = 0
    @State private var truncatedString: String?
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private var isTruncated: Bool { truncatedString != nil }

    var body: some View {
        Text(isExpanded ? text : (truncatedString ?? text))
            .font(font)
            .foregroundStyle(textColor)
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                maxHeight: isExpanded ? max(fullHeight, collapsedHeight) : collapsedHeight,
                alignment: .topLeading
            )
            .clipped()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { updateWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, new in updateWidth(new) }
            })
            .contentShape(Rectangle())
            .onTapGesture {
                guard isTruncated else { return }
                withAnimation(animation) { isExpanded.toggle() }
            }
    }

    private func updateWidth(_ width: CGFloat) {
        guard width > 0, width != availableWidth else { return }
        availableWidth = width
        recalculate()
    }

    private func recalculate() {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = lineSpacing
        ps.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: platformFont, .paragraphStyle: ps]
        let size = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)

        fullHeight = ceil(NSAttributedString(string: text, attributes: attrs)
            .boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        collapsedHeight = ceil(platformFont.lineHeight * CGFloat(lineLimit) + lineSpacing * CGFloat(lineLimit - 1))

        guard fullHeight > collapsedHeight + 2 else { truncatedString = nil; return }

        let ellipsis = "\u{2026}"
        let words = wordSegments(text)
        var lo = 0, hi = words.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = words[0..<mid].joined().trimmingTrailingWhitespace + ellipsis
            let h = ceil(NSAttributedString(string: candidate, attributes: attrs)
                .boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            if h <= collapsedHeight + 2 { lo = mid } else { hi = mid - 1 }
        }
        truncatedString = lo > 0 ? words[0..<lo].joined().trimmingTrailingWhitespace + ellipsis : ellipsis
    }

    private func wordSegments(_ text: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inWord = false
        for ch in text {
            if ch.isWhitespace || ch.isNewline {
                current.append(ch)
                inWord = false
            } else {
                if !inWord && !current.isEmpty { segments.append(current); current = "" }
                current.append(ch)
                inWord = true
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}

private extension String {
    var trimmingTrailingWhitespace: String {
        replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }
}

// MARK: - UIActivityViewController Wrapper

/// Wraps UIActivityViewController for SwiftUI. Uses a temp file URL
/// (outside iCloud) so iOS shows "Send a Copy" instead of "Collaborate".
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
