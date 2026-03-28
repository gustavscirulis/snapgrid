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
    let gridItemRects: [String: CGRect]
    var onDismissing: ((String) -> Void)?
    var onClose: () -> Void

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
        gridItemRects: [String: CGRect],
        onDismissing: ((String) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        _items = State(initialValue: items)
        self.startIndex = startIndex
        self.sourceRect = sourceRect
        self.screenSize = screenSize
        self.thumbnailImage = thumbnailImage
        self.gridItemRects = gridItemRects
        self.onDismissing = onDismissing
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
        _closeTargetFrame = State(initialValue: sourceRect)
    }

    // MARK: - Computed Properties

    private var backdropOpacity: Double {
        if !isExpanded { return 0 }
        let dragProgress = min(abs(dismissOffset) / 300.0, 1.0)
        return 1.0 - dragProgress * 0.5
    }

    private var dismissScale: CGFloat {
        let progress = min(abs(dismissOffset) / 400.0, 1.0)
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
            // 1. Backdrop
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            // 2. Adjacent images — only after hero, hidden during close
            if heroComplete && !isClosing {
                if currentIndex > 0 {
                    adjacentItemView(for: items[currentIndex - 1])
                        .offset(x: -screenSize.width + swipeOffset)
                }
                if currentIndex < items.count - 1 {
                    adjacentItemView(for: items[currentIndex + 1])
                        .offset(x: screenSize.width + swipeOffset)
                }
            }

            // 3. Current content — hero image OR settled ScrollView
            if heroComplete && !isClosing {
                settledContentView(finalFrame: finalFrame)
                    .offset(x: swipeOffset)
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
                        .offset(zoomPanOffset)
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
            .position(x: finalFrame.midX, y: finalFrame.midY)
            .offset(y: -contentOffset)

            // Metadata — positioned so top starts near screen bottom (peek)
            GeometryReader { _ in
                DetailMetadataSection(item: item, stage: metadataStage)
                    .id(item.id)
                    .frame(width: max(min(finalFrame.width, screen.width - 32), 300))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: metadataTopY - contentOffset)
            }
            .opacity(metadataOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(settledDragGesture)
        .simultaneousGesture(pinchGesture)
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    handleDoubleTap(at: value.location)
                }
        )
        // Dismiss visual effects
        .offset(y: dismissOffset)
        .scaleEffect(dismissOffset > 0 ? dismissScale : 1.0)
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
        UIScreen.main.bounds.height * 0.25
    }

    /// Metadata starts faded (0.3), reaches full opacity over 60pt of scroll
    private var metadataOpacity: Double {
        let base = 0.3
        let progress = min(contentOffset / 60, 1.0)
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
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let tx = value.translation.width
                let ty = value.translation.height

                // Determine gesture mode on first call
                if !gestureActive {
                    gestureActive = true
                    if isZoomed {
                        gestureMode = .zoomPan
                        zoomPanLastOffset = zoomPanOffset
                    } else if contentOffset > 0 {
                        // Metadata visible — only allow scroll
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

                switch gestureMode {
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
                        // Dragged past top → transition to dismiss
                        contentOffset = 0
                        dismissOffset = -proposed
                    } else if proposed > maxContentOffset {
                        let overshoot = proposed - maxContentOffset
                        contentOffset = maxContentOffset + log2(1 + overshoot) * 8
                        dismissOffset = 0
                    } else {
                        contentOffset = proposed
                        dismissOffset = 0
                    }
                case .none:
                    break
                }
            }
            .onEnded { value in
                let mode = gestureMode
                gestureActive = false
                gestureMode = .none

                switch mode {
                case .zoomPan:
                    zoomPanLastOffset = zoomPanOffset

                case .swipe:
                    let velocity = value.predictedEndTranslation.width - value.translation.width
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
                    if dismissOffset > 0 {
                        // Was scrolling but dragged past top → treat as dismiss
                        if dismissOffset > 100 || value.predictedEndTranslation.height > 300 {
                            close()
                        } else {
                            withAnimation(SnapSpring.standard) {
                                dismissOffset = 0
                            }
                        }
                        contentOffset = 0
                    } else {
                        // Snap to nearest target
                        let velocity = -(value.predictedEndTranslation.height - value.translation.height)
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
                    }

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
            // Apply correction: sourceRect is ground truth for the original item.
            // Preference-based rects may have a systematic offset (e.g. from
            // off-screen TabView pages), so anchor to sourceRect.
            let originalItemId = items[startIndex].id
            var correctedRect = targetRect
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
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        newPlayer.play()
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
    @State private var isDescriptionExpanded = false

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
                    let needsTruncation = result.imageContext.count > 60
                    Text(isDescriptionExpanded || !needsTruncation ? result.imageContext : truncateAtWord(result.imageContext, maxChars: 60))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                        .opacity(stage >= 3 ? 1 : 0)
                        .animation(MetadataReveal.spring, value: stage)
                        .onTapGesture {
                            withAnimation(MetadataReveal.spring) {
                                isDescriptionExpanded.toggle()
                            }
                        }
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

    private func truncateAtWord(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let prefix = text.prefix(maxChars)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
