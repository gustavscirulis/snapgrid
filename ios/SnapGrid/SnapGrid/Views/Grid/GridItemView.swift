import SwiftUI

struct GridItemView: View {
    let item: SnapGridItem
    let width: CGFloat
    var isSelected: Bool = false
    var onSelect: ((SnapGridItem, CGRect, UIImage?) -> Void)?
    @State private var thumbnail: UIImage?
    @State private var loadFailed = false

    private var height: CGFloat {
        width / item.gridAspectRatio
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail image
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
            } else if loadFailed {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: width, height: height)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Tap to retry")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .onTapGesture {
                        loadFailed = false
                        Task { await loadThumbnail() }
                    }
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
        .opacity(isSelected ? 0 : 1)
        .overlay(
            // Invisible tap target that captures frame at tap time
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let frame = geo.frame(in: .global)
                        onSelect?(item, frame, thumbnail)
                    }
            }
        )
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let cache = ThumbnailCache.shared

        // Try thumbnail first (fast, no wait — avoids 120s timeout for missing files)
        if let thumbURL = item.thumbnailURL,
           let loaded = await cache.loadImage(for: thumbURL) {
            thumbnail = loaded
            return
        }

        // Fall back to media file (wait for iCloud download if needed)
        if let mediaURL = item.mediaURL,
           let loaded = await cache.loadImageWhenReady(for: mediaURL, timeout: 180) {
            thumbnail = loaded
            return
        }

        loadFailed = true
    }
}
