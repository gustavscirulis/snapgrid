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
 * CLOSE
 *    0ms   backdrop 0.8 → 0
 *          images: hero springs back to sourceFrame
 *          videos: floating layer springs back to gridFrame
 *  ~360ms  overlay removed, grid cell reappears
 *
 * The floating video layer is a SEPARATE view in ContentView's ZStack.
 * This overlay only manages the backdrop, image hero, and close triggers.
 * ───────────────────────────────────────────────────────── */

struct HeroDetailOverlay: View {
    let item: MediaItem
    let sourceFrame: CGRect
    let onAnimationComplete: () -> Void

    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var image: NSImage?
    @State private var scrollEnabled = false
    @State private var isLoadingFullRes = false
    @FocusState private var isFocused: Bool

    private var isTallImage: Bool {
        !item.isVideo && item.aspectRatio < 0.5
    }

    init(item: MediaItem, sourceFrame: CGRect, onAnimationComplete: @escaping () -> Void) {
        self.item = item
        self.sourceFrame = sourceFrame
        self.onAnimationComplete = onAnimationComplete
        _image = State(initialValue: ImageCacheService.shared.image(forKey: item.id))
    }

    var body: some View {
        GeometryReader { geo in
            let windowSize = geo.size
            let finalFrame = computeFinalFrame(windowSize: windowSize, item: item)
            let currentFrame = isExpanded ? finalFrame : sourceFrame

            ZStack {
                // Backdrop
                Color.black
                    .opacity(isExpanded ? 0.80 : 0.0)
                    .ignoresSafeArea()
                    .onTapGesture { triggerClose() }

                // Image — hero animation (also serves as video placeholder until AVPlayer renders)
                if let image {
                    if isTallImage {
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
                        .id(item.id)
                    } else {
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
                            .id(item.id)
                    }
                }

                // Video — tap target only. The FloatingVideoLayer renders the actual video.
                if item.isVideo {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: finalFrame.width, height: finalFrame.height)
                        .position(x: finalFrame.midX, y: finalFrame.midY)
                        .onTapGesture { triggerClose() }
                }
            }
            // Keep floating video layer in sync with window resizes
            .onChange(of: finalFrame) { _, newFrame in
                if item.isVideo && isExpanded && !isClosing {
                    videoPreview.updateDetailFrame(newFrame)
                }
            }
            .task {
                isFocused = true

                if item.isVideo {
                    if image == nil {
                        await loadThumbnail()
                    }
                    isLoadingFullRes = true

                    let hasHoverPreview = videoPreview.player != nil
                        && videoPreview.activeItemId == item.id

                    let url = MediaStorageService.shared.mediaURL(filename: item.filename)

                    let suggestedName = item.analysisResult?.patterns.first?.name

                    if hasHoverPreview {
                        // Hover preview exists — animate both backdrop and video together
                        withAnimation(SnapSpring.hero) {
                            isExpanded = true
                            videoPreview.transitionToDetail(
                                itemId: item.id, url: url, finalFrame: finalFrame, suggestedName: suggestedName
                            )
                        }
                    } else {
                        // No hover (keyboard open) — place video at detail frame instantly
                        videoPreview.transitionToDetail(
                            itemId: item.id, url: url, finalFrame: finalFrame, suggestedName: suggestedName
                        )
                        withAnimation(SnapSpring.hero) {
                            isExpanded = true
                        }
                    }
                    // Wait for the player to buffer its first frame, then hide indicator
                    await waitForPlayerReady()
                } else {
                    if image == nil {
                        await loadThumbnail()
                    }
                    isLoadingFullRes = true
                    withAnimation(SnapSpring.hero) {
                        isExpanded = true
                    }
                    if isTallImage {
                        try? await Task.sleep(for: .milliseconds(500))
                        scrollEnabled = true
                    }
                    await loadFullResImage()
                    withAnimation(.easeOut(duration: 0.2)) {
                        isLoadingFullRes = false
                    }
                }
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

    private func triggerClose() {
        guard !isClosing else { return }
        isClosing = true
        scrollEnabled = false

        withAnimation(SnapSpring.hero) {
            isExpanded = false
            if item.isVideo {
                videoPreview.transitionToGrid()
            }
        } completion: {
            if item.isVideo {
                videoPreview.completeTransitionToGrid()
            }
            onAnimationComplete()
        }
    }

    // MARK: - Image Loading

    private func loadThumbnail() async {
        if let cached = ImageCacheService.shared.image(forKey: item.id) {
            self.image = cached
            return
        }
        let itemId = item.id
        let filename = item.filename
        let loaded: NSImage? = await Task.detached(priority: .userInitiated) {
            let storage = MediaStorageService.shared
            if storage.thumbnailExists(id: itemId) {
                return NSImage(contentsOf: storage.thumbnailURL(id: itemId))
            }
            return NSImage(contentsOf: storage.mediaURL(filename: filename))
        }.value
        if let loaded {
            self.image = loaded
        }
    }

    private func loadFullResImage() async {
        guard !item.isVideo else { return }
        let itemId = item.id
        let filename = item.filename
        let loaded: NSImage? = await Task.detached(priority: .utility) {
            return NSImage(contentsOf: MediaStorageService.shared.mediaURL(filename: filename))
        }.value
        if let loaded {
            self.image = loaded
            ImageCacheService.shared.setImage(loaded, forKey: itemId)
        }
    }

    // MARK: - Drag to Export

    private func makeDragProvider() -> NSItemProvider {
        appState.isDraggingFromApp = true
        let url = MediaStorageService.shared.mediaURL(filename: item.filename)
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        if let name = item.analysisResult?.patterns.first?.name {
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
                .frame(width: 96, height: 96 / item.aspectRatio)
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
        // Poll until the player has buffered enough to render
        while item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        withAnimation(.easeOut(duration: 0.2)) { isLoadingFullRes = false }
    }
}
