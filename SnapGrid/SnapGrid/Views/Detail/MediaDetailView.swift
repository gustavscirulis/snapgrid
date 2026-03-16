import SwiftUI
import AVKit

struct MediaDetailView: View {
    let item: MediaItem
    let allItems: [MediaItem]
    let onClose: () -> Void
    let onNavigate: (String) -> Void
    let onRetryAnalysis: (MediaItem) -> Void

    @State private var image: NSImage?
    @State private var isLoading = true

    /// AnimatedImageModal.tsx:65 — originalHeight > originalWidth * 2
    private var isTallImage: Bool {
        !item.isVideo && item.aspectRatio < 0.5
    }

    private var currentIndex: Int? {
        allItems.firstIndex(where: { $0.id == item.id })
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.80)  // AnimatedImageModal.tsx:571 — bg-black/80
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()
                }

                Spacer()

                // Media content
                if item.isVideo {
                    VideoPlayer(player: AVPlayer(url: MediaStorageService.shared.mediaURL(filename: item.filename)))
                        .aspectRatio(item.aspectRatio, contentMode: .fit)
                        .frame(maxWidth: 1200, maxHeight: 800)
                    Spacer()
                } else if let image {
                    if isTallImage {
                        // AnimatedImageModal.tsx:67-79 — tall images scroll vertically, fit to width
                        ScrollView(.vertical) {
                            ZoomableImageView(image: image)
                                .aspectRatio(item.aspectRatio, contentMode: .fit)
                                .frame(maxWidth: 1200)
                        }
                    } else {
                        ZoomableImageView(image: image)
                            .aspectRatio(item.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: 1200, maxHeight: 800)
                        Spacer()
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: 400, maxHeight: 400)
                    Spacer()
                } else {
                    Spacer()
                }

                // Metadata panel
                if let result = item.analysisResult {
                    VStack(spacing: 12) {
                        // Pattern tags
                        if !result.patterns.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(result.patterns, id: \.name) { pattern in
                                    HStack(spacing: 4) {
                                        Text(pattern.name)
                                            .font(.system(size: 13, weight: .medium))
                                        Text("\(Int(pattern.confidence * 100))%")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.snapMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }

                        // Context
                        if !result.imageContext.isEmpty {
                            Text(result.imageContext)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(3)
                                .frame(maxWidth: 600)
                        }
                    }
                    .padding()
                    .padding(.bottom, 8)
                } else if item.analysisError != nil {
                    VStack(spacing: 8) {
                        Text("Analysis failed")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        if let error = item.analysisError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(2)
                        }
                        Button("Retry Analysis") {
                            onRetryAnalysis(item)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .padding(.bottom, 8)
                } else if item.isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Analyzing...")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding()
                    .padding(.bottom, 8)
                }
            }
        }
        .onExitCommand { onClose() }
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
        .task {
            await loadImage()
        }
        .onChange(of: item.id) {
            isLoading = true
            image = nil
            Task { await loadImage() }
        }
    }

    private func loadImage() async {
        guard !item.isVideo else {
            isLoading = false
            return
        }
        let url = MediaStorageService.shared.mediaURL(filename: item.filename)
        image = NSImage(contentsOf: url)
        isLoading = false
    }

    private func navigatePrevious() {
        guard let idx = currentIndex, idx > 0 else { return }
        onNavigate(allItems[idx - 1].id)
    }

    private func navigateNext() {
        guard let idx = currentIndex, idx < allItems.count - 1 else { return }
        onNavigate(allItems[idx + 1].id)
    }
}
