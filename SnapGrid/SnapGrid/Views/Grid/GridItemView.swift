import SwiftUI
import AppKit

struct GridItemView: View {
    let item: MediaItem
    let width: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    private var height: CGFloat {
        width / item.aspectRatio
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.snapMuted)
                        .frame(width: width, height: height)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }

            // Video badge
            if item.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
                    .padding(8)
            }

            // Delete button (hover only)
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            // Bottom overlay: pattern tags, analyzing state, or error (always visible)
            VStack {
                Spacer()

                if item.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Analyzing...")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(8)
                } else if item.analysisError != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Failed")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(8)
                } else if let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                    HStack {
                        FlowLayout(spacing: 4) {
                            ForEach(patterns.prefix(4), id: \.name) { pattern in
                                Text(pattern.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial.opacity(0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: width, height: height, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.snapAccent : Color.clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onToggleSelect()
            } else {
                onSelect()
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let storage = MediaStorageService.shared
        let url = storage.thumbnailExists(id: item.id)
            ? storage.thumbnailURL(id: item.id)
            : storage.mediaURL(filename: item.filename)

        if let image = NSImage(contentsOf: url) {
            self.thumbnail = image
        }
    }
}
