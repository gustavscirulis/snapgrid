import SwiftUI
import AVKit

struct FullScreenImageOverlay: View {
    let item: SnapGridItem
    let sourceRect: CGRect
    let screenSize: CGSize
    let thumbnailImage: UIImage?
    var onClose: () -> Void

    @State private var isPresented = false
    @State private var animationComplete = false
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false
    @State private var player: AVPlayer?

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)

    /// Full-screen frame: image fitted to screen width, centered vertically
    private var fullScreenFrame: CGRect {
        let aspect = item.aspectRatio
        let w = screenSize.width
        let h = w / aspect
        let y = (screenSize.height - h) / 2
        return CGRect(x: 0, y: max(y, 0), width: w, height: min(h, screenSize.height))
    }

    /// The current animated rect (switches between source and full-screen)
    private var currentRect: CGRect {
        isPresented ? fullScreenFrame : sourceRect
    }

    private var currentCornerRadius: CGFloat {
        isPresented ? 0 : 12
    }

    /// The image to display (full-res if loaded, otherwise thumbnail)
    private var displayImage: UIImage? {
        image ?? thumbnailImage
    }

    private var backdropOpacity: Double {
        if !isPresented { return 0 }
        let dragProgress = min(abs(dragOffset) / 300.0, 1.0)
        return 1.0 - dragProgress * 0.5
    }

    var body: some View {
        ZStack {
            // Backdrop — fades independently
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()
                .onTapGesture { close() }

            if animationComplete {
                // Phase B: fully open — scrollable content with metadata
                scrollableContent
                    .offset(y: dragOffset)
                    .gesture(dismissDragGesture)
            } else {
                // Phase A/C: animating — positioned image only
                animatingImage
            }

            // Close button
            if animationComplete {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Close")
                        .padding(.top, 54)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            loadFullImage()
            prepareVideoIfNeeded()
            // Trigger open animation on next frame
            Task { @MainActor in
                withAnimation(spring) {
                    isPresented = true
                }
            }
            // After spring settles, switch to scroll content (instant, no animation)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))
                animationComplete = true
            }
        }
    }

    // MARK: - Phase A/C: Animating image

    private var animatingImage: some View {
        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: isPresented ? .fit : .fill)
                    .frame(width: currentRect.width, height: currentRect.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: currentRect.width, height: currentRect.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius))
        .position(x: currentRect.midX, y: currentRect.midY)
    }

    // MARK: - Phase B: Scrollable content

    private var scrollableContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Media fills viewport
                mediaContent
                    .frame(width: screenSize.width, height: screenSize.height)
                    .clipped()

                // Metadata below the fold
                MetadataPanel(item: item)
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 60)
            }
        }
        .scrollDisabled(isZoomed)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if item.isVideo, let player {
            VideoPlayer(player: player)
        } else if let displayImage {
            ZoomableImageView(image: displayImage, isZoomed: $isZoomed)
        } else {
            Rectangle()
                .fill(Color.snapDarkMuted)
                .overlay {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                }
        }
    }

    // MARK: - Gestures

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isZoomed else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else { return }
                if abs(value.translation.height) > 100 ||
                    abs(value.predictedEndTranslation.height) > 300 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Actions

    private func close() {
        player?.pause()
        // Phase C: swap back to positioned image for close animation
        withAnimation(nil) {
            animationComplete = false
            dragOffset = 0
        }
        // Animate back to source rect
        Task { @MainActor in
            withAnimation(spring) {
                isPresented = false
            }
        }
        // After animation completes, remove overlay entirely
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            onClose()
        }
    }

    private func loadFullImage() {
        guard let url = item.mediaURL, !item.isVideo else {
            isLoading = false
            return
        }
        Task {
            image = await ThumbnailCache.shared.loadImage(for: url)
            isLoading = false
        }
    }

    private func prepareVideoIfNeeded() {
        guard item.isVideo, let url = item.mediaURL else { return }
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        newPlayer.play()
    }
}
