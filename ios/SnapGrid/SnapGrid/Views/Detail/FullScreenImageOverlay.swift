import SwiftUI
import AVKit

struct FullScreenImageOverlay: View {
    let items: [MediaItem]
    let startIndex: Int
    let sourceRect: CGRect
    let screenSize: CGSize
    let thumbnailImage: UIImage?
    let gridItemRects: [String: CGRect]
    var onDismissing: ((String) -> Void)?
    var onClose: () -> Void

    @State private var currentIndex: Int = 0
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

    // Hero animation target (resolved at dismiss time)
    @State private var heroTargetRect: CGRect?

    // Horizontal swipe state
    @State private var swipeOffset: CGFloat = 0
    @State private var adjacentImages: [String: UIImage] = [:]  // keyed by item id

    // Gesture mode tracking — locked per gesture
    @State private var gestureActive = false
    private enum GestureMode { case none, dismiss, scroll, zoomPan, swipe }
    @State private var gestureMode: GestureMode = .none

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    // Zoom constants
    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 4.0
    private let doubleTapZoomScale: CGFloat = 2.5

    /// Current item derived from index
    private var item: MediaItem {
        items[currentIndex]
    }

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
        if isPresented {
            return fullScreenFrame
        }
        return heroTargetRect ?? sourceRect
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
                ZStack(alignment: .top) {
                    // Previous image (visible during swipe)
                    if currentIndex > 0 {
                        adjacentPageContent(for: items[currentIndex - 1])
                            .frame(width: screenSize.width, height: screenSize.height)
                            .offset(x: -screenSize.width + swipeOffset)
                    }

                    // Current item content
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
                    .offset(x: swipeOffset, y: -contentOffset + dismissOffset)
                    .scaleEffect(dismissOffset > 0 ? dismissScale : 1.0)

                    // Next image (visible during swipe)
                    if currentIndex < items.count - 1 {
                        adjacentPageContent(for: items[currentIndex + 1])
                            .frame(width: screenSize.width, height: screenSize.height)
                            .offset(x: screenSize.width + swipeOffset)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)

                // Pattern pills (non-interactive)
                if !isZoomed && contentOffset < 10 && dismissOffset == 0 && swipeOffset == 0 {
                    patternOverlay
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Page counter
                if items.count > 1 && !isZoomed && contentOffset < 10 && dismissOffset == 0 {
                    VStack {
                        Text("\(currentIndex + 1) / \(items.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 60)
                        Spacer()
                    }
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
            currentIndex = startIndex
            impactFeedback.prepare()
            loadFullImage()
            prepareVideoIfNeeded()
            preloadAdjacentImages()
            withAnimation(spring) {
                isPresented = true
            } completion: {
                animationComplete = true
            }
        }
    }

    // MARK: - Adjacent page content (simple image, no zoom/scroll)

    @ViewBuilder
    private func adjacentPageContent(for adjacentItem: MediaItem) -> some View {
        if let img = adjacentImages[adjacentItem.id] {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let thumbURL = adjacentItem.thumbnailURL,
                  let cached = ThumbnailCache.shared.image(for: thumbURL) {
            // Use cache-only lookup — no file I/O on the main thread
            Image(uiImage: cached)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(Color.snapDarkMuted)
                .overlay {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                }
        }
    }

    // MARK: - Pattern pills overlay

    private var patternOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                if let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
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
                    .frame(width: currentRect.width, height: currentRect.height, alignment: .top)
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

    // MARK: - Unified interaction gesture (handles dismiss, scroll, zoom pan, and swipe)

    private var interactionGesture: some Gesture {
        DragGesture()
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
                        // Metadata is visible — only allow vertical scroll
                        gestureMode = .scroll
                        contentOffsetAtGestureStart = contentOffset
                    } else if abs(tx) > abs(ty) {
                        // Horizontal movement dominates — swipe between images
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
                        width: zoomPanLastOffset.width + value.translation.width,
                        height: zoomPanLastOffset.height + value.translation.height
                    )
                case .swipe:
                    var proposed = tx
                    // Rubber-band at edges
                    if (currentIndex == 0 && proposed > 0) ||
                       (currentIndex == items.count - 1 && proposed < 0) {
                        proposed = proposed * 0.3
                    }
                    swipeOffset = proposed
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

                case .swipe:
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let threshold = screenSize.width * 0.3
                    let velocityThreshold: CGFloat = 200

                    var newIndex = currentIndex
                    if swipeOffset < -threshold || velocity < -velocityThreshold {
                        // Swiped left → next image
                        newIndex = min(currentIndex + 1, items.count - 1)
                    } else if swipeOffset > threshold || velocity > velocityThreshold {
                        // Swiped right → previous image
                        newIndex = max(currentIndex - 1, 0)
                    }

                    if newIndex != currentIndex {
                        // Navigate to new image
                        let targetOffset: CGFloat = newIndex > currentIndex ? -screenSize.width : screenSize.width
                        impactFeedback.impactOccurred()
                        onDismissing?(items[newIndex].id)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            swipeOffset = targetOffset
                        } completion: {
                            withAnimation(nil) {
                                currentIndex = newIndex
                                swipeOffset = 0
                            }
                            resetImageState()
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            swipeOffset = 0
                        }
                    }

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
            heroTargetRect = correctedRect

            withAnimation(nil) {
                animationComplete = false
                contentOffset = 0
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                isZoomed = false
            }
            withAnimation(spring) {
                isPresented = false
                dismissOffset = 0
            } completion: {
                onClose()
            }
        } else {
            // Grid cell not visible — slide down and fade
            withAnimation(.easeOut(duration: 0.25)) {
                dismissOffset = screenSize.height
                isPresented = false
            } completion: {
                onClose()
            }
        }
    }

    private func resetImageState() {
        image = nil
        isLoading = true
        isZoomed = false
        zoomScale = minZoomScale
        zoomLastScale = minZoomScale
        zoomPanOffset = .zero
        zoomPanLastOffset = .zero
        contentOffset = 0
        contentOffsetAtGestureStart = 0
        dismissOffset = 0
        player?.pause()
        player = nil

        loadFullImage()
        prepareVideoIfNeeded()
        preloadAdjacentImages()
    }

    private func loadFullImage() {
        guard let url = item.mediaURL, !item.isVideo else {
            isLoading = false
            return
        }
        Task {
            image = await ThumbnailCache.shared.loadImage(for: url).image
            isLoading = false
        }
    }

    private func prepareVideoIfNeeded() {
        guard item.isVideo, let url = item.mediaURL else { return }
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        newPlayer.play()
    }

    private func preloadAdjacentImages() {
        // Evict images we no longer need — keep at most current ± 1
        var keepIds: Set<String> = [item.id]
        if currentIndex > 0 { keepIds.insert(items[currentIndex - 1].id) }
        if currentIndex < items.count - 1 { keepIds.insert(items[currentIndex + 1].id) }
        for key in adjacentImages.keys where !keepIds.contains(key) {
            adjacentImages.removeValue(forKey: key)
        }

        // Preload previous
        if currentIndex > 0 {
            let prevItem = items[currentIndex - 1]
            if adjacentImages[prevItem.id] == nil, let url = prevItem.mediaURL ?? prevItem.thumbnailURL {
                Task {
                    if let img = await ThumbnailCache.shared.loadImage(for: url).image {
                        adjacentImages[prevItem.id] = img
                    }
                }
            }
        }
        // Preload next
        if currentIndex < items.count - 1 {
            let nextItem = items[currentIndex + 1]
            if adjacentImages[nextItem.id] == nil, let url = nextItem.mediaURL ?? nextItem.thumbnailURL {
                Task {
                    if let img = await ThumbnailCache.shared.loadImage(for: url).image {
                        adjacentImages[nextItem.id] = img
                    }
                }
            }
        }
    }
}
