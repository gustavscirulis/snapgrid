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
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var image: NSImage?
    @FocusState private var isFocused: Bool

    init(item: MediaItem, sourceFrame: CGRect, onAnimationComplete: @escaping () -> Void) {
        self.item = item
        self.sourceFrame = sourceFrame
        self.onAnimationComplete = onAnimationComplete
        if !item.isVideo {
            _image = State(initialValue: ImageCacheService.shared.image(forKey: item.id))
        }
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

                // Image — hero animation (non-video only)
                if let image, !item.isVideo {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: currentFrame.width, height: currentFrame.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12))
                        .onTapGesture { triggerClose() }
                        .position(x: currentFrame.midX, y: currentFrame.midY)
                        .id(item.id)
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
                    let hasHoverPreview = videoPreview.player != nil
                        && videoPreview.activeItemId == item.id

                    let url = MediaStorageService.shared.mediaURL(filename: item.filename)

                    if hasHoverPreview {
                        // Hover preview exists — animate both backdrop and video together
                        withAnimation(SnapSpring.hero) {
                            isExpanded = true
                            videoPreview.transitionToDetail(
                                itemId: item.id, url: url, finalFrame: finalFrame
                            )
                        }
                    } else {
                        // No hover (keyboard open) — place video at detail frame instantly
                        videoPreview.transitionToDetail(
                            itemId: item.id, url: url, finalFrame: finalFrame
                        )
                        withAnimation(SnapSpring.hero) {
                            isExpanded = true
                        }
                    }
                } else {
                    if image == nil {
                        await loadImage()
                    }
                    withAnimation(SnapSpring.hero) {
                        isExpanded = true
                    }
                    await loadFullResImage()
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

    private func loadImage() async {
        guard !item.isVideo else { return }
        if let cached = ImageCacheService.shared.image(forKey: item.id) {
            self.image = cached
            return
        }
        let url = MediaStorageService.shared.mediaURL(filename: item.filename)
        if let loaded = NSImage(contentsOf: url) {
            self.image = loaded
        }
    }

    private func loadFullResImage() async {
        let url = MediaStorageService.shared.mediaURL(filename: item.filename)
        if let loaded = NSImage(contentsOf: url) {
            self.image = loaded
        }
    }
}
