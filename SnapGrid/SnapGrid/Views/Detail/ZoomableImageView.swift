import SwiftUI

struct ZoomableImageView: View {
    let image: NSImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Velocity tracking for momentum
    @State private var velocity: CGSize = .zero
    @State private var lastDragTime: Date = .now
    @State private var lastDragTranslation: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    /// Critically-damped spring for momentum deceleration.
    /// dampingFraction 1.0 = no bounce, natural deceleration matching Apple's scrolling physics.
    private let momentumSpring = Animation.interpolatingSpring(
        mass: 1.0, stiffness: 60, damping: 16, initialVelocity: 0
    )

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = lastScale * value.magnification
                        scale = min(max(newScale, minScale), maxScale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= minScale {
                            withAnimation(SnapSpring.standard) {
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

                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        // Project the final offset based on captured velocity
                        let projectedOffset = CGSize(
                            width: offset.width + velocity.width * 0.3,
                            height: offset.height + velocity.height * 0.3
                        )
                        withAnimation(momentumSpring) {
                            offset = projectedOffset
                        }
                        lastOffset = projectedOffset
                        velocity = .zero
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(SnapSpring.standard) {
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
}
