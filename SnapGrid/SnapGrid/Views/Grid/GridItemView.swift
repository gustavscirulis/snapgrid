import SwiftUI
import AppKit

struct GridItemView: View {
    let item: MediaItem
    let width: CGFloat
    let isSelected: Bool
    let spaces: [Space]
    let activeSpaceId: String?
    let selectedCount: Int
    let onSelect: () -> Void
    let onToggleSelect: () -> Void
    let onShiftSelect: () -> Void
    let onDelete: () -> Void
    let onAssignToSpace: (String?) -> Void
    let onRetryAnalysis: () -> Void

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    private var height: CGFloat {
        width / item.aspectRatio
    }

    /// Whether this item is part of a multi-selection context menu
    private var isBulk: Bool {
        isSelected && selectedCount > 1
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
                VStack {
                    Spacer()
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
                }
                .frame(width: width, height: height)
            }

            // Delete button (hover only, top-right)
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
                .transition(.opacity)
            }

            // Remove from space button (hover only, top-left)
            if isHovered && activeSpaceId != nil {
                VStack {
                    HStack {
                        Button { onAssignToSpace(nil) } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(width: width, height: height)
                .transition(.opacity)
            }

            // Bottom overlay: analyzing shimmer, error badge, or hover-only pattern tags
            VStack {
                Spacer()

                if item.isAnalyzing {
                    ShimmerText("Analyzing...")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                } else if item.analysisError != nil {
                    Button(action: onRetryAnalysis) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Retry")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                } else if isHovered, let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                    // Gradient backdrop + pattern tags (hover only)
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.black.opacity(0.7), .clear],
                            startPoint: .bottom,
                            endPoint: .center
                        )

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
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: width, height: height, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))  // ImageCard.tsx:96 — rounded-lg (--radius: 0.8rem)
        .padding(isSelected ? 1 : 0)  // ring-offset-1 gap
        .overlay(
            RoundedRectangle(cornerRadius: 13)  // 12 + 1px offset
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)  // ImageCard.tsx:97 — ring-2 ring-blue-500
        )
        .shadow(  // ImageCard.tsx:96 — shadow-sm / hover:shadow-md
            color: .black.opacity(isHovered ? 0.1 : 0.05),
            radius: isHovered ? 6 : 2,
            x: 0,
            y: isHovered ? 4 : 1
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .draggable(TransferableFileURL(url: MediaStorageService.shared.mediaURL(filename: item.filename))) {
            // Multi-select: stacked preview with count badge
            if isBulk, let thumbnail {
                ZStack {
                    // Stack layers (up to 3 behind the front)
                    ForEach(Array((0..<min(selectedCount, 3)).reversed()), id: \.self) { i in
                        if i > 0 {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.snapMuted)
                                .frame(width: 100, height: 100 / item.aspectRatio)
                                .rotationEffect(.degrees(Double(i) * 3))
                                .opacity(1.0 - Double(i) * 0.2)
                        }
                    }

                    // Front image
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100 / item.aspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Count badge
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(selectedCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.snapAccent)
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .offset(x: 8, y: -8)
                }
                .frame(width: 120, height: (100 / item.aspectRatio) + 16)
            } else if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120 / item.aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.snapMuted)
                    .frame(width: 120, height: 80)
            }
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                onToggleSelect()
            } else if flags.contains(.shift) {
                onShiftSelect()
            } else {
                onSelect()
            }
        }
        .contextMenu {
            // Move to space submenu
            Menu(isBulk ? "Move \(selectedCount) items to" : "Move to") {
                ForEach(spaces) { space in
                    Button {
                        onAssignToSpace(space.id)
                    } label: {
                        if item.space?.id == space.id {
                            Label(space.name, systemImage: "checkmark")
                        } else {
                            Text(space.name)
                        }
                    }
                }
            }

            // Remove from space
            if activeSpaceId != nil {
                Button(isBulk ? "Remove \(selectedCount) from Space" : "Remove from Space") {
                    onAssignToSpace(nil)
                }
            }

            Divider()

            Button("Retry Analysis") {
                onRetryAnalysis()
            }

            Divider()

            Button(isBulk ? "Delete \(selectedCount) Items" : "Delete", role: .destructive) {
                onDelete()
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // Check memory cache first
        if let cached = ImageCacheService.shared.image(forKey: item.id) {
            self.thumbnail = cached
            return
        }

        let storage = MediaStorageService.shared
        let url = storage.thumbnailExists(id: item.id)
            ? storage.thumbnailURL(id: item.id)
            : storage.mediaURL(filename: item.filename)

        if let image = NSImage(contentsOf: url) {
            ImageCacheService.shared.setImage(image, forKey: item.id)
            self.thumbnail = image
        }
    }
}

// MARK: - Shimmer Text

/// Animated shimmer text that sweeps a highlight gradient across the label
struct ShimmerText: View {
    let text: String
    @State private var phase: CGFloat = 0

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
                .linearGradient(
                    colors: [
                        .white.opacity(0.5),
                        .white.opacity(0.9),
                        .white.opacity(0.5),
                    ],
                    startPoint: .init(x: phase - 0.3, y: 0.5),
                    endPoint: .init(x: phase + 0.3, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}
