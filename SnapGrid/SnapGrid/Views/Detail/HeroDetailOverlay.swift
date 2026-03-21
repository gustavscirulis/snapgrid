import SwiftUI
import AVKit

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD — Thumbnail → Detail Hero
 *
 * OPEN
 *    0ms   thumbnail hidden, backdrop 0 → 0.8, image springs
 *          from sourceFrame → finalFrame, cornerRadius 12 → 16
 *  360ms   spring settles, close button + metadata fade in
 *
 * CLOSE
 *    0ms   UI hidden, backdrop 0.8 → 0, image springs back
 *          to sourceFrame, cornerRadius 16 → 12
 *  400ms   overlay removed, thumbnail reappears
 *
 * NAVIGATE (arrow keys)
 *    0ms   image crossfades (0.2s), metadata crossfades
 * ───────────────────────────────────────────────────────── */

// MARK: - Spring Config

/// Matches Electron's framer-motion { damping: 30, stiffness: 300 }
private let heroSpring = Animation.spring(response: 0.36, dampingFraction: 0.87)

// MARK: - HeroDetailOverlay

struct HeroDetailOverlay: View {
    let item: MediaItem
    let allItems: [MediaItem]
    let sourceFrame: CGRect
    let onNavigate: (String) -> Void
    let onRetryAnalysis: (MediaItem) -> Void
    let onAnimationComplete: () -> Void

    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var showUI = false
    @State private var image: NSImage?

    private var isTallImage: Bool {
        !item.isVideo && item.aspectRatio < 0.5
    }

    private var currentIndex: Int? {
        allItems.firstIndex(where: { $0.id == item.id })
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

                // Image container
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: currentFrame.width, height: currentFrame.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12))
                        .position(x: currentFrame.midX, y: currentFrame.midY)
                        .id(item.id)
                } else if item.isVideo {
                    // Video: use simple centered appearance (no hero morph)
                    if isExpanded {
                        VideoPlayer(player: AVPlayer(url: MediaStorageService.shared.mediaURL(filename: item.filename)))
                            .aspectRatio(item.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: finalFrame.width, maxHeight: finalFrame.height)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .position(x: finalFrame.midX, y: finalFrame.midY)
                    }
                }

                // Close button + metadata (fade in after expansion)
                if showUI && !isClosing {
                    VStack(spacing: 0) {
                        // Close button
                        HStack {
                            Spacer()
                            Button(action: triggerClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 32, height: 32)
                                    .background(.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding()
                        }

                        Spacer()

                        // Metadata panel
                        metadataPanel
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
                }
            }
        }
        .ignoresSafeArea()
        .onExitCommand { triggerClose() }
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
        .task {
            await loadImage()
            // Start the hero animation after image is loaded
            withAnimation(heroSpring) {
                isExpanded = true
            }
            // Show UI after spring settles
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeOut(duration: 0.2)) {
                showUI = true
            }
        }
        .onChange(of: item.id) {
            // Arrow key navigation: crossfade, don't re-run hero
            image = nil
            Task { await loadImage() }
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
        showUI = false

        withAnimation(heroSpring) {
            isExpanded = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            onAnimationComplete()
        }
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        guard let idx = currentIndex, idx > 0 else { return }
        onNavigate(allItems[idx - 1].id)
    }

    private func navigateNext() {
        guard let idx = currentIndex, idx < allItems.count - 1 else { return }
        onNavigate(allItems[idx + 1].id)
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

    // MARK: - Metadata Panel

    @ViewBuilder
    private var metadataPanel: some View {
        if let result = item.analysisResult {
            VStack(spacing: 12) {
                if !result.patterns.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(result.patterns, id: \.name) { pattern in
                            HStack(spacing: 4) {
                                Text(pattern.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(Int(pattern.confidence * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.snapMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                if !result.imageContext.isEmpty {
                    Text(result.imageContext)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                        .frame(maxWidth: 600)
                }
            }
            .padding()
            .padding(.bottom, 8)
        } else if item.analysisError != nil {
            VStack(spacing: 8) {
                Text("Analysis failed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                if let error = item.analysisError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                }
                Button("Retry Analysis") {
                    onRetryAnalysis(item)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .padding(.bottom, 8)
        } else if item.isAnalyzing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Analyzing...")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding()
            .padding(.bottom, 8)
        }
    }
}
