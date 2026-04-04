import SwiftUI

/// Shared drag preview thumbnail used by GridItemView and HeroDetailOverlay.
struct DragThumbnailPreview: View {
    let image: NSImage?
    let aspectRatio: CGFloat
    var bulkCount: Int? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 96 / aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.snapMuted)
                    .frame(width: 96, height: 64)
            }
            if let bulkCount, bulkCount > 1 {
                Text("\(bulkCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.snapAccent)
                    .clipShape(Circle())
                    .offset(x: 6, y: -6)
            }
        }
        .opacity(0.85)
    }
}
