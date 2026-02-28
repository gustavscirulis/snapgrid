import SwiftUI

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var isZoomed: Bool
    @Binding var panOffset: CGSize
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let doubleTapScale: CGFloat = 2.5

    init(image: UIImage, isZoomed: Binding<Bool>, panOffset: Binding<CGSize>) {
        self.image = image
        self._isZoomed = isZoomed
        self._panOffset = panOffset
    }

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(panOffset)
                .frame(width: geo.size.width, height: geo.size.height)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let raw = lastScale * value.magnification
                            scale = rubberBand(raw, min: minScale, max: maxScale)
                            isZoomed = scale > minScale
                        }
                        .onEnded { _ in
                            let clamped = min(max(scale, minScale), maxScale)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                scale = clamped
                                if clamped <= minScale {
                                    panOffset = .zero
                                }
                            }
                            lastScale = clamped
                            isZoomed = clamped > minScale
                        }
                )
                .onTapGesture(count: 2) { location in
                    let viewCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > minScale {
                            scale = minScale
                            lastScale = minScale
                            panOffset = .zero
                            isZoomed = false
                        } else {
                            scale = doubleTapScale
                            lastScale = doubleTapScale
                            panOffset = CGSize(
                                width: (viewCenter.x - location.x) * (doubleTapScale - 1),
                                height: (viewCenter.y - location.y) * (doubleTapScale - 1)
                            )
                            isZoomed = true
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .accessibilityLabel("Zoomable image")
                .accessibilityHint("Pinch to zoom, double tap to toggle zoom")
                .accessibilityAddTraits(.isImage)
        }
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
}
