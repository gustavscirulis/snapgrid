import SwiftUI
import AVKit

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD — Thumbnail → Detail Hero
 *
 * OPEN
 *    0ms   thumbnail hidden, backdrop 0 → 0.8, image springs
 *          from sourceFrame → finalFrame, cornerRadius 12 → 16
 *
 * CLOSE
 *    0ms   backdrop 0.8 → 0, image springs back
 *          to sourceFrame, cornerRadius 16 → 12
 *  400ms   overlay removed, thumbnail reappears
 * ───────────────────────────────────────────────────────── */

// MARK: - Spring Config

/// Matches Electron's framer-motion { damping: 30, stiffness: 300 }
/// See AnimationTokens.swift — SnapSpring.hero

// MARK: - HeroDetailOverlay

struct HeroDetailOverlay: View {
    let item: MediaItem
    let sourceFrame: CGRect
    let onAnimationComplete: () -> Void

    @Environment(VideoPreviewManager.self) private var videoPreview
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var image: NSImage?
    @State private var detailPlayer: AVPlayer?
    @FocusState private var isFocused: Bool

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

                // Image container
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: currentFrame.width, height: currentFrame.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12))
                        .onTapGesture { triggerClose() }
                        .position(x: currentFrame.midX, y: currentFrame.midY)
                        .id(item.id)
                } else if item.isVideo, let player = detailPlayer {
                    // Video: use shared player for seamless handoff from hover preview
                    if isExpanded {
                        VideoPlayer(player: player)
                            .aspectRatio(item.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: finalFrame.width, maxHeight: finalFrame.height)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .position(x: finalFrame.midX, y: finalFrame.midY)
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
        .task {
            isFocused = true
            if item.isVideo {
                // Claim the hover preview player (seamless handoff, continues from current position)
                if let claimed = videoPreview.claimForDetail() {
                    detailPlayer = claimed
                } else {
                    // No hover preview active (e.g., opened via keyboard) — create fresh
                    let player = AVPlayer(url: MediaStorageService.shared.mediaURL(filename: item.filename))
                    detailPlayer = player
                    player.play()
                }
            } else {
                await loadImage()
            }
            withAnimation(SnapSpring.hero) {
                isExpanded = true
            }
        }
    }

    // MARK: - Final Frame Computation

    /// Matches AnimatedImageModal.tsx:20-97
    private func computeFinalFrame(windowSize: CGSize, item: MediaItem) -> CGRect {
        let maxW = windowSize.width * 0.95
        let maxH = (windowSize.height * 0.95) - 80

        if !item.isVideo && item.aspectRatio < 0.5 {
            // Tall image: fit to width, cap height
            let w = min(CGFloat(item.width), maxW)
            let h = min(w / item.aspectRatio, windowSize.height - 80)
            return CGRect(x: (windowSize.width - w) / 2, y: 40, width: w, height: h)
        }

        let widthScale = maxW / CGFloat(item.width)
        let heightScale = maxH / CGFloat(item.height)
        let scale = min(widthScale, heightScale, 1.0)
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
        } completion: {
            videoPreview.releaseFromDetail()
            detailPlayer = nil
            onAnimationComplete()
        }
    }

    // MARK: - Image Loading

    private func loadImage() async {
        guard !item.isVideo else { return }

        // Check memory cache first
        if let cached = ImageCacheService.shared.image(forKey: item.id) {
            self.image = cached
            return
        }

        let url = MediaStorageService.shared.mediaURL(filename: item.filename)
        if let loaded = NSImage(contentsOf: url) {
            self.image = loaded
        }
    }
}
