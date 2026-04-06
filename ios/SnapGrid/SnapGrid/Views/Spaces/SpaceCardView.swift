import SwiftUI

struct SpaceCardView: View {
    let space: Space
    @State private var thumbnails: [UIImage] = []

    private var sortedItems: [MediaItem] {
        space.items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.snapDarkMuted)

                if thumbnails.count >= 4 {
                    miniGrid
                } else if let first = thumbnails.first {
                    Image(uiImage: first)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 4) {
                Text(space.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text("\(space.items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .task {
            await loadThumbnails()
        }
    }

    // MARK: - 2x2 Mini Grid

    private var miniGrid: some View {
        let gap: CGFloat = 2
        return GeometryReader { geo in
            let size = (geo.size.width - gap) / 2
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    miniThumbnail(thumbnails[0], size: size)
                    miniThumbnail(thumbnails[1], size: size)
                }
                HStack(spacing: gap) {
                    miniThumbnail(thumbnails[2], size: size)
                    miniThumbnail(thumbnails[3], size: size)
                }
            }
        }
    }

    private func miniThumbnail(_ image: UIImage, size: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipped()
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnails() async {
        let itemsToLoad = Array(sortedItems.prefix(4))
        let cache = ThumbnailCache.shared
        var loaded: [UIImage] = []

        for item in itemsToLoad {
            if let thumbURL = item.thumbnailURL {
                let (image, _) = await cache.loadImage(for: thumbURL, targetPixelWidth: 200)
                if let image {
                    loaded.append(image)
                    continue
                }
            }
            if let mediaURL = item.mediaURL {
                let (image, _) = await cache.loadImage(for: mediaURL, targetPixelWidth: 200)
                if let image {
                    loaded.append(image)
                }
            }
        }

        thumbnails = loaded
    }
}
