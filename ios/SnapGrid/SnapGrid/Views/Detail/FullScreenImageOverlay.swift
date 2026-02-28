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
    @State private var isZoomed = false
    @State private var player: AVPlayer?

    // Dismiss gesture state (drag down from top)
    @State private var dismissOffset: CGFloat = 0

    // Content scroll state (drag up to reveal metadata)
    @State private var contentOffset: CGFloat = 0
    @State private var contentOffsetAtGestureStart: CGFloat = 0

    // Zoom state (owned here — NOT on a child view, to avoid gesture conflicts)
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomLastScale: CGFloat = 1.0
    @State private var zoomPanOffset: CGSize = .zero
    @State private var zoomPanLastOffset: CGSize = .zero

    // Gesture mode tracking — locked per gesture
    @State private var gestureActive = false
    private enum GestureMode { case none, dismiss, scroll, zoomPan }
    @State private var gestureMode: GestureMode = .none

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    // Zoom constants
    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 4.0
    private let doubleTapZoomScale: CGFloat = 2.5

    /// How far to scroll up to fully reveal metadata
    private var metadataSnapOffset: CGFloat {
        screenSize.height * 0.45
    }

    // MARK: - Computed layout properties

    private var fullScreenFrame: CGRect {
        let aspect = item.aspectRatio
        let w = screenSize.width
        let h = w / aspect
        let y = (screenSize.height - h) / 2
        return CGRect(x: 0, y: max(y, 0), width: w, height: min(h, screenSize.height))
    }

    private var currentRect: CGRect {
        isPresented ? fullScreenFrame : sourceRect
    }

    private var currentCornerRadius: CGFloat {
        isPresented ? 0 : 12
    }

    private var displayImage: UIImage? {
        image ?? thumbnailImage
    }

    private var backdropOpacity: Double {
        if !isPresented { return 0 }
        let dragProgress = min(abs(dismissOffset) / 300.0, 1.0)
        return 1.0 - dragProgress * 0.5
    }

    private var dismissScale: CGFloat {
        let progress = min(abs(dismissOffset) / 400.0, 1.0)
        return 1.0 - progress * 0.1
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Backdrop
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            if animationComplete {
                // Visual content (non-interactive — gestures are on the layer above)
                VStack(spacing: 0) {
                    mediaContent
                        .frame(width: screenSize.width, height: screenSize.height)
                        .clipped()

                    MetadataPanel(item: item)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 60)
                        .frame(width: screenSize.width)
                }
                .offset(y: -contentOffset + dismissOffset)
                .scaleEffect(dismissOffset > 0 ? dismissScale : 1.0)
                .allowsHitTesting(false)
                .transition(.opacity)

                // Pattern pills (non-interactive)
                if !isZoomed && contentOffset < 10 && dismissOffset == 0 {
                    patternOverlay
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Full-screen gesture layer — covers everything so drags work anywhere
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(interactionGesture)
                    .simultaneousGesture(pinchGesture)
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { value in
                                handleDoubleTap(at: value.location)
                            }
                    )
                    .overlay(alignment: .topTrailing) {
                        // Close button as overlay child — tap gets priority over drag
                        if !isZoomed && contentOffset < 50 {
                            Button(action: close) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .accessibilityLabel("Close")
                            .padding(.top, 54)
                            .padding(.trailing, 16)
                            .transition(.opacity)
                        }
                    }
            } else {
                animatingImage
            }
        }
        .ignoresSafeArea()
        .onAppear {
            impactFeedback.prepare()
            loadFullImage()
            prepareVideoIfNeeded()
            withAnimation(spring) {
                isPresented = true
            } completion: {
                animationComplete = true
            }
        }
    }

    // MARK: - Pattern pills overlay

    private var patternOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                if let patterns = item.patterns, !patterns.isEmpty {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.3))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(patterns.prefix(6), id: \.name) { pattern in
                                Text(pattern.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 50)
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
        .position(x: currentRect.midX, y: currentRect.midY + dismissOffset)
    }

    // MARK: - Media content (rendered directly — no child gestures)

    @ViewBuilder
    private var mediaContent: some View {
        if item.isVideo, let player {
            VideoPlayer(player: player)
        } else if let displayImage {
            GeometryReader { geo in
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
                    .offset(zoomPanOffset)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        } else {
            Rectangle()
                .fill(Color.snapDarkMuted)
                .overlay {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                }
        }
    }

    // MARK: - Unified interaction gesture (handles dismiss, scroll, and zoom pan)

    private var interactionGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let ty = value.translation.height

                // Determine gesture mode on first call
                if !gestureActive {
                    gestureActive = true
                    if isZoomed {
                        gestureMode = .zoomPan
                        zoomPanLastOffset = zoomPanOffset
                    } else if contentOffset <= 0 && ty > 0 {
                        gestureMode = .dismiss
                    } else {
                        gestureMode = .scroll
                        contentOffsetAtGestureStart = contentOffset
                    }
                }

                switch gestureMode {
                case .zoomPan:
                    zoomPanOffset = CGSize(
                        width: zoomPanLastOffset.width + value.translation.width,
                        height: zoomPanLastOffset.height + value.translation.height
                    )
                case .dismiss:
                    dismissOffset = max(0, ty)
                case .scroll:
                    let proposed = contentOffsetAtGestureStart - ty
                    if proposed < 0 {
                        // Dragged past the top → transition into dismiss behavior
                        contentOffset = 0
                        dismissOffset = -proposed
                    } else if proposed > metadataSnapOffset {
                        let overshoot = proposed - metadataSnapOffset
                        contentOffset = metadataSnapOffset + log2(1 + overshoot) * 8
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

                case .dismiss:
                    if dismissOffset > 100 || value.predictedEndTranslation.height > 300 {
                        close()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            dismissOffset = 0
                        }
                    }

                case .scroll:
                    if dismissOffset > 0 {
                        // Was scrolling but dragged past top → treat as dismiss
                        if dismissOffset > 100 || value.predictedEndTranslation.height > 300 {
                            close()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                dismissOffset = 0
                            }
                        }
                        contentOffset = 0
                        contentOffsetAtGestureStart = 0
                    } else {
                        let velocity = -(value.predictedEndTranslation.height - value.translation.height)
                        let projectedOffset = contentOffset + velocity * 0.3
                        let snapTarget: CGFloat
                        if projectedOffset > metadataSnapOffset * 0.35 {
                            snapTarget = metadataSnapOffset
                        } else {
                            snapTarget = 0
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            contentOffset = snapTarget
                        }
                        contentOffsetAtGestureStart = snapTarget
                    }

                case .none:
                    break
                }
            }
    }

    // MARK: - Pinch-to-zoom gesture

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = zoomLastScale * value.magnification
                zoomScale = rubberBand(raw, min: minZoomScale, max: maxZoomScale)
                isZoomed = zoomScale > minZoomScale
            }
            .onEnded { _ in
                let clamped = min(max(zoomScale, minZoomScale), maxZoomScale)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    zoomScale = clamped
                    if clamped <= minZoomScale {
                        zoomPanOffset = .zero
                    }
                }
                zoomLastScale = clamped
                isZoomed = clamped > minZoomScale
            }
    }

    // MARK: - Double-tap to zoom

    private func handleDoubleTap(at location: CGPoint) {
        guard contentOffset < 10 else { return }
        let viewCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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

    // MARK: - Actions

    private func close() {
        player?.pause()
        impactFeedback.impactOccurred()
        // Switch to animating image instantly, but keep dismissOffset
        // so the image stays at its dragged position (no visual jump)
        withAnimation(nil) {
            animationComplete = false
            contentOffset = 0
            zoomScale = minZoomScale
            zoomLastScale = minZoomScale
            zoomPanOffset = .zero
            isZoomed = false
        }
        // Animate from current position (including dismissOffset) to grid
        withAnimation(spring) {
            isPresented = false
            dismissOffset = 0
        } completion: {
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
