import SwiftUI

struct GridItemView: View {
    let item: SnapGridItem
    let width: CGFloat
    @State private var thumbnail: UIImage?

    private var height: CGFloat {
        width / item.aspectRatio
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail image
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: width, height: height)
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.3))
                    }
            }

            // Video indicator
            if item.isVideo {
                HStack {
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let url = item.thumbnailURL ?? item.mediaURL else { return }

        // Try loading — if file isn't downloaded from iCloud yet,
        // retry a few times with delay to let the download finish
        for attempt in 0..<5 {
            if let loaded = await ThumbnailCache.shared.loadImage(for: url) {
                thumbnail = loaded
                return
            }
            if attempt < 4 {
                try? await Task.sleep(for: .seconds(Double(attempt + 1)))
            }
        }
    }
}
