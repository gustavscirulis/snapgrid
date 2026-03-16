import SwiftUI

struct ZoomableImageView: View {
    let image: NSImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Momentum state
    @State private var velocity: CGSize = .zero
    @State private var lastDragTime: Date = .now
    @State private var lastDragTranslation: CGSize = .zero
    @State private var momentumTimer: Timer?

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let friction: CGFloat = 0.95
    private let minVelocity: CGFloat = 0.5

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        stopMomentum()
                        let newScale = lastScale * value.magnification
                        scale = min(max(newScale, minScale), maxScale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= minScale {
                            withAnimation(.spring(response: 0.3)) {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > minScale else { return }
                        stopMomentum()

                        let now = Date.now
                        let dt = now.timeIntervalSince(lastDragTime)
                        if dt > 0 && dt < 0.1 {
                            let dx = value.translation.width - lastDragTranslation.width
                            let dy = value.translation.height - lastDragTranslation.height
                            // Normalize to ~16ms frame (matching Electron's approach)
                            let factor = 0.016 / dt
                            velocity = CGSize(width: dx * factor, height: dy * factor)
                        }
                        lastDragTime = now
                        lastDragTranslation = value.translation

                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                        startMomentum()
                    }
            )
            .onTapGesture(count: 2) {
                stopMomentum()
                withAnimation(.spring(response: 0.3)) {
                    if scale > minScale {
                        scale = minScale
                        lastScale = minScale
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
    }

    private func startMomentum() {
        guard scale > minScale else { return }
        let v = velocity
        guard abs(v.width) > minVelocity || abs(v.height) > minVelocity else { return }

        momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            velocity = CGSize(
                width: velocity.width * friction,
                height: velocity.height * friction
            )

            offset = CGSize(
                width: offset.width + velocity.width,
                height: offset.height + velocity.height
            )
            lastOffset = offset

            if abs(velocity.width) < minVelocity && abs(velocity.height) < minVelocity {
                timer.invalidate()
                momentumTimer = nil
            }
        }
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        velocity = .zero
    }
}
