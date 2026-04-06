import SwiftUI

struct ZoomableImageView: View {
    let image: NSImage
    let frameSize: CGSize
    let windowSize: CGSize
    @Binding var zoomScale: CGFloat
    @Binding var isZoomed: Bool
    @Binding var trackpadPanDelta: CGSize
    let isTallImage: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    // MARK: - Internal gesture state

    @State private var lastScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var panLastOffset: CGSize = .zero
    /// Captures panLastOffset when a trackpad scroll gesture begins
    @State private var trackpadPanBaseOffset: CGSize = .zero

    @State private var velocity: CGSize = .zero
    @State private var lastDragTime: Date = .now
    @State private var lastDragTranslation: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let doubleTapScale: CGFloat = 2.5
    private let edgeInset: CGFloat = 40

    private let momentumSpring = Animation.interpolatingSpring(
        mass: 1.0, stiffness: 60, damping: 16, initialVelocity: 0
    )

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: isTallImage ? .fit : .fill)
            .frame(width: frameSize.width * zoomScale, height: frameSize.height * zoomScale)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .offset(panOffset)
            .frame(width: frameSize.width, height: frameSize.height)
            .contentShape(Rectangle())
            .gesture(magnifyGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) { location in
                handleDoubleTap(at: location)
            }
            .onTapGesture(count: 1) {
                if !isZoomed {
                    onTap()
                }
            }
            .onChange(of: zoomScale) { _, newScale in
                if newScale <= minScale && lastScale != minScale {
                    lastScale = minScale
                    panOffset = .zero
                    panLastOffset = .zero
                    trackpadPanBaseOffset = .zero
                    velocity = .zero
                }
            }
            .onChange(of: trackpadPanDelta) { _, delta in
                guard isZoomed else { return }
                if delta == .zero {
                    let clamped = clampedPanOffset(panOffset, scale: zoomScale)
                    withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
                        panOffset = clamped
                    }
                    panLastOffset = clamped
                    trackpadPanBaseOffset = clamped
                } else {
                    let raw = CGSize(
                        width: trackpadPanBaseOffset.width + delta.width,
                        height: trackpadPanBaseOffset.height + delta.height
                    )
                    panOffset = rubberBandPanOffset(raw, scale: zoomScale)
                    panLastOffset = panOffset
                }
            }
    }

    // MARK: - Pinch-to-Zoom Gesture

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = lastScale * value.magnification
                let prevZoom = zoomScale
                let newZoom = rubberBandScale(raw)

                // Focal-point: adjust pan so the pinch center stays fixed
                if prevZoom > 0 && newZoom != prevZoom {
                    let anchor = CGPoint(
                        x: value.startAnchor.x * frameSize.width,
                        y: value.startAnchor.y * frameSize.height
                    )
                    let imageCenterX = frameSize.width / 2 + panOffset.width
                    let imageCenterY = frameSize.height / 2 + panOffset.height
                    let ratio = newZoom / prevZoom
                    let dx = -(anchor.x - imageCenterX) * (ratio - 1)
                    let dy = -(anchor.y - imageCenterY) * (ratio - 1)
                    panOffset.width += dx
                    panOffset.height += dy
                    panLastOffset.width += dx
                    panLastOffset.height += dy
                }

                zoomScale = newZoom
                isZoomed = zoomScale > minScale
            }
            .onEnded { _ in
                let clamped = min(max(zoomScale, minScale), maxScale)
                withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
                    zoomScale = clamped
                    if clamped <= minScale {
                        panOffset = .zero
                    } else {
                        panOffset = clampedPanOffset(panOffset, scale: clamped)
                    }
                }
                lastScale = clamped
                panLastOffset = panOffset
                isZoomed = clamped > minScale
            }
    }

    // MARK: - Drag/Pan Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > minScale else { return }

                let now = Date.now
                let dt = now.timeIntervalSince(lastDragTime)
                if dt > 0 && dt < 0.1 {
                    let dx = value.translation.width - lastDragTranslation.width
                    let dy = value.translation.height - lastDragTranslation.height
                    let factor = 0.016 / dt
                    velocity = CGSize(width: dx * factor, height: dy * factor)
                }
                lastDragTime = now
                lastDragTranslation = value.translation

                let raw = CGSize(
                    width: panLastOffset.width + value.translation.width,
                    height: panLastOffset.height + value.translation.height
                )
                panOffset = rubberBandPanOffset(raw, scale: zoomScale)
            }
            .onEnded { _ in
                guard zoomScale > minScale else { return }

                let projected = CGSize(
                    width: panOffset.width + velocity.width * 0.3,
                    height: panOffset.height + velocity.height * 0.3
                )
                let target = clampedPanOffset(projected, scale: zoomScale)
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : momentumSpring) {
                    panOffset = target
                }
                panLastOffset = target
                trackpadPanBaseOffset = target
                velocity = .zero
            }
    }

    // MARK: - Double-Tap

    private func handleDoubleTap(at location: CGPoint) {
        let center = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)
        withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
            if zoomScale > minScale {
                zoomScale = minScale
                panOffset = .zero
                isZoomed = false
            } else {
                zoomScale = doubleTapScale
                let rawOffset = CGSize(
                    width: (center.x - location.x) * (doubleTapScale - 1),
                    height: (center.y - location.y) * (doubleTapScale - 1)
                )
                panOffset = clampedPanOffset(rawOffset, scale: doubleTapScale)
                isZoomed = true
            }
        }
        lastScale = zoomScale
        panLastOffset = panOffset
        trackpadPanBaseOffset = panOffset
    }

    // MARK: - Pan Boundary Helpers

    private func maxPanOffset(scale: CGFloat) -> CGSize {
        let availableW = windowSize.width - edgeInset * 2
        let availableH = windowSize.height - edgeInset * 2
        return CGSize(
            width: max(0, (frameSize.width * scale - availableW) / 2),
            height: max(0, (frameSize.height * scale - availableH) / 2)
        )
    }

    private func clampedPanOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        guard scale > minScale else { return .zero }
        let limit = maxPanOffset(scale: scale)
        return CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }

    private func rubberBandPanOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        guard scale > minScale else { return .zero }
        let limit = maxPanOffset(scale: scale)
        return CGSize(
            width: rubberBandAxis(offset.width, limit: limit.width),
            height: rubberBandAxis(offset.height, limit: limit.height)
        )
    }

    // MARK: - Rubber-Band Helpers

    private func rubberBandScale(_ value: CGFloat) -> CGFloat {
        if value < minScale {
            return minScale - log2(1 + minScale - value) * 0.15
        } else if value > maxScale {
            return maxScale + log2(1 + value - maxScale) * 0.15
        }
        return value
    }

    private func rubberBandAxis(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        if value > limit {
            let overshoot = value - limit
            return limit + log2(1 + overshoot / 12) * 12
        } else if value < -limit {
            let overshoot = -value - limit
            return -limit - log2(1 + overshoot / 12) * 12
        }
        return value
    }
}
