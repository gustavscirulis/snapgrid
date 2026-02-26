import SwiftUI

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var isZoomed: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    init(image: UIImage, isZoomed: Binding<Bool> = .constant(false)) {
        self.image = image
        self._isZoomed = isZoomed
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = lastScale * value.magnification
                        scale = min(max(newScale, minScale), maxScale)
                        isZoomed = scale > minScale
                    }
                    .onEnded { _ in
                        lastScale = scale
                        isZoomed = scale > minScale
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
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > minScale {
                        scale = minScale
                        lastScale = minScale
                        offset = .zero
                        lastOffset = .zero
                        isZoomed = false
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                        isZoomed = true
                    }
                }
            }
    }
}
