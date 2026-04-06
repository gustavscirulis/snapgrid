import SwiftUI
import AVFoundation

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD — Thumbnail → Detail Hero
 *
 * OPEN
 *    0ms   thumbnail hidden, backdrop 0 → 0.8
 *          images: hero image springs from sourceFrame → finalFrame
 *          videos: floating layer springs from gridFrame → finalFrame
 *
 * CLOSE (original item)
 *    0ms   backdrop 0.8 → 0
 *          images: hero springs back to sourceFrame
 *          videos: floating layer springs back to gridFrame
 *  ~360ms  overlay removed, grid cell reappears
 *
 * CLOSE (after navigation)
 *    0ms   fade out backdrop + image
 *  ~300ms  overlay removed
 *
 * NAVIGATION
 *    Horizontal trackpad swipe or arrow keys slide current image out,
 *    next/previous image slides in from the opposite edge.
 *    Uses NSEvent scroll wheel monitoring for trackpad two-finger swipe.
 *
 * METADATA REVEAL
 *    After hero animation completes, metadata section fades in
 *    with staggered timing: title → pills → description → file info.
 *    Scrolling down reveals metadata with a fade mask.
 *
 * The floating video layer is a SEPARATE view in ContentView's ZStack.
 * This overlay only manages the backdrop, image hero, and close triggers.
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

struct HeroDetailOverlay: View {
    let startIndex: Int
    let sourceFrame: CGRect
    let onAnimationComplete: () -> Void
    let onCurrentItemChanged: ((String) -> Void)?
    let onShare: ((String, CGRect) -> Void)?
    let onRedoAnalysis: ((String) -> Void)?
    let onDelete: ((String) -> Void)?
    let onAssignToSpace: ((String, String?) -> Void)?
    let spaces: [Space]
    let activeSpaceId: String?

    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Captured at open time — stays stable even when parent re-filters.
    @State private var items: [MediaItem]
    @State private var currentIndex: Int
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var image: NSImage?
    @State private var scrollEnabled = false
    @State private var isLoadingFullRes = false
    @State private var heroComplete = false
    @State private var hasNavigated = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isNavigating = false
    @State private var adjacentImages: [String: NSImage] = [:]
    @State private var loadTask: Task<Void, Never>?
    @State private var closeTargetFrame: CGRect
    @State private var lastWindowWidth: CGFloat = 800
    @State private var trackpadScroll = TrackpadScrollState()
    @State private var scrollOffset: CGFloat = 0
    @State private var metadataStage: Int = 0
    @State private var revealTask: Task<Void, Never>?
    @State private var navigationFallbackTask: Task<Void, Never>?
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomPanDelta: CGSize = .zero
    @FocusState private var isFocused: Bool

    private var currentItem: MediaItem { items[currentIndex] }

    private var isTallImage: Bool {
        !currentItem.isVideo && currentItem.aspectRatio < 0.5
    }

    init(
        items: [MediaItem],
        startIndex: Int,
        sourceFrame: CGRect,
        onAnimationComplete: @escaping () -> Void,
        onCurrentItemChanged: ((String) -> Void)? = nil,
        onShare: ((String, CGRect) -> Void)? = nil,
        onRedoAnalysis: ((String) -> Void)? = nil,
        onDelete: ((String) -> Void)? = nil,
        onAssignToSpace: ((String, String?) -> Void)? = nil,
        spaces: [Space] = [],
        activeSpaceId: String? = nil
    ) {
        _items = State(initialValue: items)
        self.startIndex = startIndex
        self.sourceFrame = sourceFrame
        self.onAnimationComplete = onAnimationComplete
        self.onCurrentItemChanged = onCurrentItemChanged
        self.onShare = onShare
        self.onRedoAnalysis = onRedoAnalysis
        self.onDelete = onDelete
        self.onAssignToSpace = onAssignToSpace
        self.spaces = spaces
        self.activeSpaceId = activeSpaceId
        _currentIndex = State(initialValue: startIndex)
        _closeTargetFrame = State(initialValue: sourceFrame)
        _image = State(initialValue: ImageCacheService.shared.image(forKey: items[startIndex].id))
    }

    var body: some View {
        GeometryReader { geo in
            let windowSize = geo.size
            let finalFrame = computeFinalFrame(windowSize: windowSize, item: currentItem)
            let currentFrame = isExpanded ? finalFrame : closeTargetFrame

            ZStack {
                // Backdrop
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.55)
                }
                .opacity(isExpanded ? 1.0 : 0.0)
                .ignoresSafeArea()
                .onTapGesture { triggerClose() }

                // Adjacent images — only after hero animation completes, never during open/close
                if heroComplete && !isClosing {
                    // Previous
                    if currentIndex > 0 {
                        adjacentItemView(for: items[currentIndex - 1], windowSize: windowSize)
                            .offset(x: -windowSize.width + swipeOffset)
                    }
                    // Next
                    if currentIndex < items.count - 1 {
                        adjacentItemView(for: items[currentIndex + 1], windowSize: windowSize)
                            .offset(x: windowSize.width + swipeOffset)
                    }
                }

                // Current content — settled ScrollView (stays visible during swipe) or position-based hero
                if heroComplete && !isClosing {
                    // SETTLED: scrollable image + metadata, slides with swipe
                    settledScrollView(image: image, finalFrame: finalFrame, windowSize: windowSize)
                        .offset(x: swipeOffset)
                } else if let image, isTallImage {
                    // HERO/SWIPE: tall image
                    ScrollView(.vertical, showsIndicators: scrollEnabled) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: currentFrame.width)
                            .onTapGesture { triggerClose() }
                    }
                    .scrollDisabled(!scrollEnabled)
                    .frame(width: currentFrame.width, height: currentFrame.height)
                    .overlay(alignment: .bottomTrailing) {
                        loadingIndicator
                    }
                    .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12))
                    .onDrag { makeDragProvider() } preview: { dragPreview }
                    .position(x: currentFrame.midX, y: currentFrame.midY)
                    .offset(x: heroComplete ? swipeOffset : 0)
                } else if let image {
                    // HERO/SWIPE: regular image
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: currentFrame.width, height: currentFrame.height)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            loadingIndicator
                        }
                        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12))
                        .onDrag { makeDragProvider() } preview: { dragPreview }
                        .onTapGesture { triggerClose() }
                        .position(x: currentFrame.midX, y: currentFrame.midY)
                        .offset(x: heroComplete ? swipeOffset : 0)
                }

                // Video — tap target only. The FloatingVideoLayer renders the actual video.
                // Disable when settled (scroll view handles taps).
                if currentItem.isVideo && !(heroComplete && !isClosing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: finalFrame.width, height: finalFrame.height)
                        .position(x: finalFrame.midX, y: finalFrame.midY)
                        .offset(x: heroComplete ? swipeOffset : 0)
                        .onTapGesture { triggerClose() }
                }
            }
            // Capture window width for navigation calculations
            .onChange(of: windowSize.width) { _, w in lastWindowWidth = w }
            .onAppear { lastWindowWidth = windowSize.width }
            // Sync swipe progress to AppState so grid thumbnails fade in/out
            .onChange(of: swipeOffset) { _, offset in
                guard heroComplete else { return }
                let progress = min(abs(offset) / max(lastWindowWidth, 1), 1.0)
                appState.detailSwipeProgress = progress
                if offset < 0 && currentIndex < items.count - 1 {
                    appState.detailSwipeTargetId = items[currentIndex + 1].id
                } else if offset > 0 && currentIndex > 0 {
                    appState.detailSwipeTargetId = items[currentIndex - 1].id
                } else {
                    appState.detailSwipeTargetId = nil
                }
            }
            // Track the current item's grid frame for close animation
            .onChange(of: appState.detailSourceFrame) { _, newFrame in
                if let newFrame {
                    closeTargetFrame = newFrame
                }
            }
            // Keep floating video layer in sync with window resizes
            .onChange(of: finalFrame) { _, newFrame in
                if currentItem.isVideo && isExpanded && !isClosing {
                    videoPreview.updateDetailFrame(newFrame)
                }
            }
            .task {
                isFocused = true
                await openItem(finalFrame: finalFrame)
                preloadAdjacentImages()
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .ignoresSafeArea()
        .onKeyPress(.escape) {
            if isZoomed {
                resetZoom()
            } else {
                triggerClose()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isNavigating && !isClosing && !isZoomed else { return .ignored }
            navigateTo(currentIndex - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isNavigating && !isClosing && !isZoomed else { return .ignored }
            navigateTo(currentIndex + 1)
            return .handled
        }
        // Trackpad scroll wheel monitoring for two-finger swipe (navigation)
        .onChange(of: trackpadScroll.cumulativeOffset) { _, offset in
            guard heroComplete && !isClosing && !isNavigating && !isZoomed && items.count > 1 else { return }
            var proposed = offset
            if (currentIndex == 0 && proposed > 0) ||
               (currentIndex == items.count - 1 && proposed < 0) {
                proposed *= 0.3
            }
            swipeOffset = proposed
        }
        // Trackpad two-finger scroll for zoom panning
        .onChange(of: trackpadScroll.scrollDelta) { _, delta in
            guard isZoomed && heroComplete && !isClosing else { return }
            zoomPanDelta = delta
        }
        .onChange(of: trackpadScroll.phase) { _, phase in
            guard phase == .ended else { return }
            if isZoomed {
                zoomPanDelta = .zero
                trackpadScroll.reset()
            } else if heroComplete && !isClosing && !isNavigating && items.count > 1 {
                evaluateSwipeEnd()
                trackpadScroll.reset()
            } else {
                trackpadScroll.reset()
                // Don't animate swipeOffset when a navigation animation owns it —
                // interrupting would prevent its completion handler from firing.
                if !isNavigating {
                    withAnimation(SnapSpring.standard(reduced: reduceMotion)) { swipeOffset = 0 }
                }
            }
        }
        .onChange(of: heroComplete) { _, complete in
            if complete && !isZoomed {
                trackpadScroll.activate()
            } else {
                trackpadScroll.deactivate()
            }
        }
        .onChange(of: isZoomed) { _, zoomed in
            trackpadScroll.trackBothAxes = zoomed
            trackpadScroll.reset()
            zoomPanDelta = .zero
        }
    }

    // MARK: - Swipe Evaluation

    private func evaluateSwipeEnd() {
        let threshold: CGFloat = 30
        let offset = swipeOffset

        if offset < -threshold && currentIndex < items.count - 1 {
            navigateTo(currentIndex + 1)
        } else if offset > threshold && currentIndex > 0 {
            navigateTo(currentIndex - 1)
        } else {
            withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
                swipeOffset = 0
            }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ newIndex: Int) {
        guard newIndex >= 0, newIndex < items.count, newIndex != currentIndex else {
            withAnimation(SnapSpring.standard(reduced: reduceMotion)) { swipeOffset = 0 }
            return
        }
        isNavigating = true
        let direction: CGFloat = newIndex > currentIndex ? -1 : 1
        let oldItem = currentItem

        // Stop video if leaving a video item
        if oldItem.isVideo {
            videoPreview.stopDetailPlayer()
        }

        // Slide current image out, adjacent image slides in
        withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
            swipeOffset = direction * lastWindowWidth
        } completion: {
            self.completeNavigation(to: newIndex)
        }

        // Safety fallback: if the completion handler is lost due to animation
        // interruption, complete the navigation after the spring settles.
        navigationFallbackTask?.cancel()
        navigationFallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, isNavigating else { return }
            completeNavigation(to: newIndex)
        }
    }

    private func completeNavigation(to newIndex: Int) {
        guard isNavigating else { return }
        navigationFallbackTask?.cancel()

        // Swap to new item without animation
        let t = Transaction(animation: nil)
        withTransaction(t) {
            currentIndex = newIndex
            hasNavigated = true
            swipeOffset = 0
            scrollEnabled = false
            metadataStage = 0
            scrollOffset = 0
            isZoomed = false
            zoomScale = 1.0
            zoomPanDelta = .zero

            // Load new image from cache or preloaded adjacents
            let newItem = items[newIndex]
            image = adjacentImages[newItem.id]
                ?? ImageCacheService.shared.image(forKey: newItem.id)
        }

        // Notify parent so grid hides correct thumbnail
        onCurrentItemChanged?(items[newIndex].id)

        // Reset swipe progress — new item is now the hidden one
        appState.detailSwipeProgress = 0
        appState.detailSwipeTargetId = nil

        // Load full-res image or start video
        loadTask?.cancel()
        loadTask = Task {
            await loadCurrentItem()
        }

        preloadAdjacentImages()
        isNavigating = false
        startMetadataReveal()
    }

    // MARK: - Item Loading

    private func openItem(finalFrame: CGRect) async {
        let item = currentItem

        if item.isVideo {
            if image == nil {
                await loadThumbnailFor(item)
            }
            isLoadingFullRes = true

            let hasHoverPreview = videoPreview.player != nil
                && videoPreview.activeItemId == item.id

            let url = MediaStorageService.shared.mediaURL(filename: item.filename)
            let suggestedName = item.analysisResult?.patterns.first?.name

            if hasHoverPreview {
                withAnimation(SnapSpring.hero(reduced: reduceMotion)) {
                    isExpanded = true
                    videoPreview.transitionToDetail(
                        itemId: item.id, url: url, finalFrame: finalFrame, suggestedName: suggestedName
                    )
                } completion: {
                    heroComplete = true
                    startMetadataReveal()
                }
            } else {
                videoPreview.transitionToDetail(
                    itemId: item.id, url: url, finalFrame: finalFrame, suggestedName: suggestedName
                )
                withAnimation(SnapSpring.hero(reduced: reduceMotion)) {
                    isExpanded = true
                } completion: {
                    heroComplete = true
                    startMetadataReveal()
                }
            }
            await waitForPlayerReady()
        } else {
            if image == nil {
                await loadThumbnailFor(item)
            }
            let mediaURL = MediaStorageService.shared.mediaURL(filename: item.filename)
            if !FileManager.default.fileExists(atPath: mediaURL.path) {
                isLoadingFullRes = true
            }
            withAnimation(SnapSpring.hero(reduced: reduceMotion)) {
                isExpanded = true
            } completion: {
                heroComplete = true
                startMetadataReveal()
            }
            if isTallImage {
                try? await Task.sleep(for: .milliseconds(500))
                scrollEnabled = true
            }
            await loadFullResImageFor(item)
            withAnimation(.easeOut(duration: 0.2)) {
                isLoadingFullRes = false
            }
        }
    }

    private func loadCurrentItem() async {
        let item = currentItem

        if item.isVideo {
            isLoadingFullRes = true
            let url = MediaStorageService.shared.mediaURL(filename: item.filename)
            let suggestedName = item.analysisResult?.patterns.first?.name
            let frame = computeFinalFrame(
                windowSize: CGSize(width: lastWindowWidth, height: NSApp.keyWindow?.frame.height ?? 800),
                item: item
            )
            videoPreview.switchDetailPlayer(itemId: item.id, url: url, frame: frame, suggestedName: suggestedName)
            await waitForPlayerReady()
        } else {
            if image == nil {
                await loadThumbnailFor(item)
            }
            let mediaURL = MediaStorageService.shared.mediaURL(filename: item.filename)
            if !FileManager.default.fileExists(atPath: mediaURL.path) {
                isLoadingFullRes = true
            }
            if isTallImage {
                try? await Task.sleep(for: .milliseconds(300))
                scrollEnabled = true
            }
            await loadFullResImageFor(item)
            withAnimation(.easeOut(duration: 0.2)) {
                isLoadingFullRes = false
            }
        }
    }

    // MARK: - Adjacent Images

    @ViewBuilder
    private func adjacentItemView(for item: MediaItem, windowSize: CGSize) -> some View {
        let frame = computeFinalFrame(windowSize: windowSize, item: item)
        let adjImage = adjacentImages[item.id] ?? ImageCacheService.shared.image(forKey: item.id)

        if let adjImage {
            Image(nsImage: adjImage)
                .resizable()
                .aspectRatio(contentMode: item.aspectRatio < 0.5 ? .fit : .fill)
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .position(x: frame.midX, y: frame.midY)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func preloadAdjacentImages() {
        let keepIds = Set(
            [currentIndex - 1, currentIndex, currentIndex + 1]
                .filter { $0 >= 0 && $0 < items.count }
                .map { items[$0].id }
        )

        for key in adjacentImages.keys where !keepIds.contains(key) {
            adjacentImages.removeValue(forKey: key)
        }

        for offset in [-1, 1] {
            let idx = currentIndex + offset
            guard idx >= 0, idx < items.count else { continue }
            let adjItem = items[idx]
            if adjacentImages[adjItem.id] != nil { continue }
            if ImageCacheService.shared.image(forKey: adjItem.id) != nil { continue }

            Task {
                if let loaded = await ImageCacheService.shared.loadThumbnail(id: adjItem.id, filename: adjItem.filename) {
                    adjacentImages[adjItem.id] = loaded
                }
            }
        }
    }

    // MARK: - Loading Indicator

    @ViewBuilder
    private var loadingIndicator: some View {
        if isLoadingFullRes && isExpanded {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .padding(6)
                .background(.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(10)
                .transition(.opacity)
        }
    }

    // MARK: - Metadata Reveal

    private func startMetadataReveal() {
        revealTask?.cancel()

        // Skip staggered reveal when reduce motion is enabled — show everything at once
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) { metadataStage = 4 }
            return
        }

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

    // MARK: - Settled Scroll View

    @ViewBuilder
    private func settledScrollView(image: NSImage?, finalFrame: CGRect, windowSize: CGSize) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: finalFrame.minY)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isZoomed { resetZoom() } else { triggerClose() }
                    }

                Group {
                    if currentItem.isVideo {
                        Color.clear
                            .frame(width: finalFrame.width, height: finalFrame.height)
                    } else if let image {
                        ZoomableImageView(
                            image: image,
                            frameSize: CGSize(width: finalFrame.width, height: finalFrame.height),
                            windowSize: windowSize,
                            zoomScale: $zoomScale,
                            isZoomed: $isZoomed,
                            trackpadPanDelta: $zoomPanDelta,
                            isTallImage: isTallImage,
                            reduceMotion: reduceMotion,
                            onTap: { triggerClose() }
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !currentItem.isVideo { loadingIndicator }
                }
                .onDrag { makeDragProvider() } preview: { dragPreview }
                .contextMenu { detailContextMenu(frame: finalFrame) }

                DetailMetadataSection(item: currentItem, stage: metadataStage) { pattern in
                    // Set search so grid re-layouts and reports new frame position
                    appState.searchText = pattern
                    // Wait for grid to re-layout and report new frame, then close to it
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        triggerClose {
                            NotificationCenter.default.post(name: .focusSearch, object: nil)
                        }
                    }
                }
                .frame(width: max(min(finalFrame.width, 550), 400))
                .padding(.top, 40)
                .padding(.bottom, 40)
                .mask(metadataFadeMask)
                .opacity(isZoomed ? 0 : 1)
                .animation(SnapSpring.fast, value: isZoomed)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(isZoomed)
        .scrollIndicators(.automatic)
        .defaultScrollAnchor(.top)
        .id(currentItem.id)  // Force new ScrollView per item, resetting scroll position
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newOffset in
            scrollOffset = newOffset
            if currentItem.isVideo && heroComplete && !isClosing {
                videoPreview.updateDetailFrame(CGRect(
                    x: finalFrame.origin.x,
                    y: finalFrame.origin.y - newOffset,
                    width: finalFrame.width,
                    height: finalFrame.height
                ))
            }
        }
    }

    private var metadataFadeMask: some View {
        let fade = max(0, 1 - scrollOffset / 60)
        return LinearGradient(
            colors: [
                .white.opacity(1 - 0.8 * fade),
                .white.opacity(1 - 0.4 * fade)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Final Frame Computation

    private func computeFinalFrame(windowSize: CGSize, item: MediaItem) -> CGRect {
        let maxW = windowSize.width * 0.95
        let maxH = (windowSize.height * 0.95) - 80

        if !item.isVideo && item.aspectRatio < 0.5 {
            let w = min(CGFloat(item.width), maxW)
            let h = min(w / item.aspectRatio, windowSize.height - 80)
            return CGRect(x: (windowSize.width - w) / 2, y: 40, width: w, height: h)
        }

        let widthScale = maxW / CGFloat(item.width)
        let heightScale = maxH / CGFloat(item.height)
        let scale = item.isVideo ? min(widthScale, heightScale) : min(widthScale, heightScale, 1.0)
        let w = CGFloat(item.width) * scale
        let h = CGFloat(item.height) * scale
        return CGRect(
            x: (windowSize.width - w) / 2,
            y: (windowSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    // MARK: - Zoom Reset

    private func resetZoom() {
        zoomPanDelta = .zero
        withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
            zoomScale = 1.0
            isZoomed = false
        }
    }

    // MARK: - Close

    private func triggerClose(then afterClose: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        heroComplete = false
        scrollEnabled = false
        scrollOffset = 0
        metadataStage = 0
        isZoomed = false
        zoomScale = 1.0
        zoomPanDelta = .zero
        revealTask?.cancel()
        navigationFallbackTask?.cancel()
        appState.detailSwipeProgress = 0
        appState.detailSwipeTargetId = nil

        if currentItem.isVideo {
            if hasNavigated {
                videoPreview.stopDetailPlayer()
            } else {
                // Original video — animate floating layer back to grid
            }
        }

        withAnimation(SnapSpring.hero(reduced: reduceMotion)) {
            isExpanded = false
            if currentItem.isVideo && !hasNavigated {
                videoPreview.transitionToGrid()
            }
        } completion: {
            if currentItem.isVideo && !hasNavigated {
                videoPreview.completeTransitionToGrid()
            }
            onAnimationComplete()
            afterClose?()
        }
    }

    // MARK: - Image Loading

    private func loadThumbnailFor(_ item: MediaItem) async {
        if let loaded = await ImageCacheService.shared.loadThumbnail(id: item.id, filename: item.filename) {
            self.image = loaded
        }
    }

    private func loadFullResImageFor(_ item: MediaItem) async {
        guard !item.isVideo else { return }
        let filename = item.filename
        let loaded: NSImage? = await Task.detached(priority: .utility) {
            return NSImage(contentsOf: MediaStorageService.shared.mediaURL(filename: filename))
        }.value
        if let loaded, !Task.isCancelled, items[currentIndex].id == item.id {
            self.image = loaded
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func detailContextMenu(frame: CGRect) -> some View {
        MediaItemContextMenu(
            spaces: spaces,
            activeSpaceId: activeSpaceId,
            currentSpaceId: currentItem.space?.id,
            onMoveToSpace: { spaceId in
                if let spaceId {
                    onAssignToSpace?(currentItem.id, spaceId)
                } else {
                    onAssignToSpace?(currentItem.id, nil)
                }
            },
            onShare: { onShare?(currentItem.id, frame) },
            onRedoAnalysis: { onRedoAnalysis?(currentItem.id) },
            onDelete: {
                triggerClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onDelete?(currentItem.id)
                }
            }
        )
    }

    // MARK: - Drag to Export

    private func makeDragProvider() -> NSItemProvider {
        appState.isDraggingFromApp = true
        let url = MediaStorageService.shared.mediaURL(filename: currentItem.filename)
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        if let name = currentItem.analysisResult?.patterns.first?.name {
            let ext = url.pathExtension
            provider.suggestedName = ext.isEmpty ? name : "\(name).\(ext)"
        }
        return provider
    }

    private var dragPreview: some View {
        DragThumbnailPreview(image: image, aspectRatio: currentItem.aspectRatio)
    }

    private func waitForPlayerReady() async {
        guard let player = videoPreview.player,
              let item = player.currentItem else {
            withAnimation(.easeOut(duration: 0.2)) { isLoadingFullRes = false }
            return
        }
        while !Task.isCancelled && item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        withAnimation(.easeOut(duration: 0.2)) { isLoadingFullRes = false }
    }
}

// MARK: - Detail Metadata Section

private struct DetailMetadataSection: View {
    let item: MediaItem
    let stage: Int
    var onSearchPattern: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Analyzing...")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if item.analysisError != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                    Text("Analysis failed")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if let result = item.analysisResult {
                if !result.imageSummary.isEmpty {
                    Text(result.imageSummary)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .stageReveal(stage: stage, threshold: 1)
                        .padding(.bottom, 10)
                }

                if !result.patterns.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(result.patterns.enumerated()), id: \.element.name) { index, pattern in
                            PatternPill(name: pattern.name, large: true)
                                .onTapGesture { onSearchPattern?(pattern.name) }
                                .opacity(stage >= 2 ? 1 : 0)
                                .offset(y: stage >= 2 ? 0 : MetadataReveal.slideDistance)
                                .animation(
                                    MetadataReveal.spring.delay(Double(index) * MetadataReveal.tagStagger),
                                    value: stage
                                )
                        }
                    }
                    .padding(.leading, -6)
                    .padding(.bottom, 18)
                }

                if hasDescription(result) {
                    Text(result.imageContext)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineSpacing(2)
                        .stageReveal(stage: stage, threshold: 3)
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
            .font(.caption.monospaced())
            .foregroundStyle(.white.opacity(0.25))
            .stageReveal(stage: stage, threshold: 4)
            .padding(.top, 16)

            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                SourceLinkButton(url: url)
                    .stageReveal(stage: stage, threshold: 4)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
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

// MARK: - Source Link Button

private struct SourceLinkButton: View {
    let url: URL
    @State private var isHovered = false

    private var label: String {
        if let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            return "View on X"
        }
        return "View source"
    }

    private var iconName: String {
        if let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            return "arrow.up.right.square"
        }
        return "link"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(isHovered ? 0.6 : 0.3))
        .onHover { isHovered = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(url)
        }
        .accessibilityLabel("View original post on X")
        .accessibilityAddTraits(.isLink)
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

// MARK: - Trackpad Scroll State

/// Monitors macOS scroll wheel events (two-finger trackpad swipe) and exposes
/// cumulative offset + phase as @Observable properties for SwiftUI to react to.
@Observable
@MainActor
final class TrackpadScrollState {
    private(set) var cumulativeOffset: CGFloat = 0
    /// Two-axis cumulative scroll delta (used for zoom panning)
    private(set) var scrollDelta: CGSize = .zero
    private(set) var phase: ScrollPhase = .idle
    // nonisolated(unsafe) so deinit can clean up the monitor from a nonisolated context.
    // The compiler suggests plain `nonisolated` but @Observable macro prevents that.
    nonisolated(unsafe) private var monitor: Any?
    private var isHorizontalLocked = false
    /// When true, tracks both axes without direction locking (for zoom pan)
    var trackBothAxes = false

    enum ScrollPhase { case idle, scrolling, ended }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }

    func activate() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    func deactivate() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        reset()
    }

    func reset() {
        if cumulativeOffset != 0 { cumulativeOffset = 0 }
        if scrollDelta != .zero { scrollDelta = .zero }
        if phase != .idle { phase = .idle }
        isHorizontalLocked = false
    }

    private func handleScroll(_ event: NSEvent) {
        // Only handle trackpad events (not mouse scroll wheel)
        guard event.hasPreciseScrollingDeltas else { return }

        if trackBothAxes {
            handleZoomPanScroll(event)
        } else {
            handleNavigationScroll(event)
        }
    }

    /// Two-axis zoom pan mode — allows momentum events for natural deceleration
    private func handleZoomPanScroll(_ event: NSEvent) {
        // New finger contact — reset and start fresh
        if event.phase == .began {
            scrollDelta = .zero
            phase = .scrolling
        }

        // Accumulate delta from both direct touch and momentum
        if event.phase == .changed || event.phase == .began {
            scrollDelta.width += event.scrollingDeltaX
            scrollDelta.height += event.scrollingDeltaY
            phase = .scrolling
        }

        // Momentum events (after finger lifts) — keep accumulating for inertia
        if event.momentumPhase == .changed || event.momentumPhase == .began {
            scrollDelta.width += event.scrollingDeltaX
            scrollDelta.height += event.scrollingDeltaY
            phase = .scrolling
        }

        // Gesture fully complete (momentum ended or finger lifted without momentum)
        let fingerEnded = event.phase == .ended || event.phase == .cancelled
        let momentumEnded = event.momentumPhase == .ended

        if momentumEnded {
            phase = .ended
        } else if fingerEnded && event.momentumPhase == [] {
            // Finger lifted but no momentum will follow (very slow gesture)
            phase = .ended
        }
    }

    /// Horizontal-only navigation mode — ignores momentum for precise control
    private func handleNavigationScroll(_ event: NSEvent) {
        guard event.momentumPhase == [] else { return }

        if event.phase == .began {
            isHorizontalLocked = false
            cumulativeOffset = 0
        }

        if event.phase == .began || event.phase == .changed {
            if !isHorizontalLocked && (abs(event.scrollingDeltaX) > 2 || abs(event.scrollingDeltaY) > 2) {
                isHorizontalLocked = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }

            if isHorizontalLocked {
                cumulativeOffset += event.scrollingDeltaX
                phase = .scrolling
            }
        }

        if event.phase == .ended || event.phase == .cancelled {
            if isHorizontalLocked {
                phase = .ended
            } else {
                reset()
            }
        }
    }
}
