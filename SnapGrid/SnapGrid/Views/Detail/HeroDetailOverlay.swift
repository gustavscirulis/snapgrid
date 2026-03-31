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
                    settledScrollView(image: image, finalFrame: finalFrame)
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
            triggerClose()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isNavigating && !isClosing else { return .ignored }
            navigateTo(currentIndex - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isNavigating && !isClosing else { return .ignored }
            navigateTo(currentIndex + 1)
            return .handled
        }
        // Trackpad scroll wheel monitoring for two-finger swipe
        .onChange(of: trackpadScroll.cumulativeOffset) { _, offset in
            guard heroComplete && !isClosing && !isNavigating && items.count > 1 else { return }
            var proposed = offset
            if (currentIndex == 0 && proposed > 0) ||
               (currentIndex == items.count - 1 && proposed < 0) {
                proposed *= 0.3
            }
            swipeOffset = proposed
        }
        .onChange(of: trackpadScroll.phase) { _, phase in
            guard heroComplete && !isClosing && !isNavigating && items.count > 1 else {
                if phase == .ended {
                    trackpadScroll.reset()
                    withAnimation(SnapSpring.standard(reduced: reduceMotion)) { swipeOffset = 0 }
                }
                return
            }
            if phase == .ended {
                evaluateSwipeEnd()
                trackpadScroll.reset()
            }
        }
        .onChange(of: heroComplete) { _, complete in
            if complete {
                trackpadScroll.activate()
            } else {
                trackpadScroll.deactivate()
            }
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
            // Swap to new item without animation
            var t = Transaction(animation: nil)
            withTransaction(t) {
                currentIndex = newIndex
                hasNavigated = true
                swipeOffset = 0
                scrollEnabled = false
                metadataStage = 0
                scrollOffset = 0

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
    private func settledScrollView(image: NSImage?, finalFrame: CGRect) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: finalFrame.minY)
                    .contentShape(Rectangle())
                    .onTapGesture { triggerClose() }

                Group {
                    if currentItem.isVideo {
                        Color.clear
                            .frame(width: finalFrame.width, height: finalFrame.height)
                    } else if let image, isTallImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: finalFrame.width)
                    } else if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: finalFrame.width, height: finalFrame.height)
                            .clipped()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !currentItem.isVideo { loadingIndicator }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onDrag { makeDragProvider() } preview: { dragPreview }
                .onTapGesture { triggerClose() }
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
                .frame(width: max(min(finalFrame.width, 500), 400))
                .padding(.top, 40)
                .padding(.bottom, 40)
                .mask(metadataFadeMask)
            }
            .frame(maxWidth: .infinity)
        }
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

    // MARK: - Close

    private func triggerClose(then afterClose: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        heroComplete = false
        scrollEnabled = false
        scrollOffset = 0
        metadataStage = 0
        revealTask?.cancel()
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
        if let loaded, items[currentIndex].id == item.id {
            self.image = loaded
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func detailContextMenu(frame: CGRect) -> some View {
        if !spaces.isEmpty {
            Menu {
                ForEach(spaces) { space in
                    Button {
                        onAssignToSpace?(currentItem.id, space.id)
                    } label: {
                        if currentItem.space?.id == space.id {
                            Label(space.name, systemImage: "checkmark")
                        } else {
                            Text(space.name)
                        }
                    }
                }
            } label: {
                Label("Move to", systemImage: "folder")
            }

            if activeSpaceId != nil {
                Button {
                    onAssignToSpace?(currentItem.id, nil)
                } label: {
                    Label("Remove from Space", systemImage: "folder.badge.minus")
                }
            }

            Divider()
        }

        Button {
            onShare?(currentItem.id, frame)
        } label: {
            Label("Share...", systemImage: "square.and.arrow.up")
        }

        Button {
            onRedoAnalysis?(currentItem.id)
        } label: {
            Label("Redo Analysis", systemImage: "arrow.clockwise")
        }

        Divider()

        Button(role: .destructive) {
            triggerClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onDelete?(currentItem.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
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

    @ViewBuilder
    private var dragPreview: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 96, height: 96 / currentItem.aspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(0.85)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 96, height: 64)
                .opacity(0.85)
        }
    }

    private func waitForPlayerReady() async {
        guard let player = videoPreview.player,
              let item = player.currentItem else {
            withAnimation(.easeOut(duration: 0.2)) { isLoadingFullRes = false }
            return
        }
        while item.status == .unknown {
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
                        .font(.body.weight(.semibold))
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
                    .padding(.bottom, 12)
                }

                if hasDescription(result) {
                    Text(result.imageContext)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
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
            .padding(.top, 12)
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
    private(set) var phase: ScrollPhase = .idle
    private var monitor: Any?
    private var isHorizontalLocked = false

    enum ScrollPhase { case idle, scrolling, ended }

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
        cumulativeOffset = 0
        phase = .idle
        isHorizontalLocked = false
    }

    private func handleScroll(_ event: NSEvent) {
        // Only handle trackpad events (not mouse scroll wheel)
        guard event.hasPreciseScrollingDeltas else { return }
        // Ignore momentum phase — only respond to direct finger contact
        guard event.momentumPhase == [] else { return }

        if event.phase == .began {
            isHorizontalLocked = false
            cumulativeOffset = 0
        }

        if event.phase == .began || event.phase == .changed {
            // Direction lock on first significant movement
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
