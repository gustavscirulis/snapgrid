import AVFoundation
import SwiftUI

// MARK: - The ONE AVPlayerLayer

/// NSView subclass that owns a single AVPlayerLayer and keeps it sized
/// to bounds on every layout pass. Uses .resizeAspect so the video is
/// never cropped — the frame is always sized to match the video's aspect
/// ratio (both in grid and detail), so .resizeAspect fills identically
/// to .resizeAspectFill without amplifying tiny aspect-ratio mismatches.
private class VideoHostView: NSView {
    let playerLayer: AVPlayerLayer
    let gradientLayer: CAGradientLayer

    /// Show/hide the bottom scrim gradient (used during grid hover).
    /// Rendered as a CALayer so it composites above the AVPlayerLayer —
    /// plain SwiftUI views can't reliably render above NSViewRepresentable content.
    var showGradient: Bool = false {
        didSet { gradientLayer.isHidden = !showGradient }
    }

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect

        gradientLayer = CAGradientLayer()
        // macOS CALayer y-axis: 0 = bottom, 1 = top
        gradientLayer.colors = [
            CGColor(gray: 0, alpha: 0.35),    // darkest at bottom
            CGColor(gray: 0, alpha: 0.1),     // subtle mid
            CGColor(gray: 0, alpha: 0),       // clear
        ]
        gradientLayer.locations = [0, 0.25, 0.45]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.isHidden = true

        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        layer?.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        gradientLayer.frame = bounds
        CATransaction.commit()
    }

    // Prevent this NSView from intercepting AppKit hit tests.
    // The floating layer is purely visual — all interaction goes through
    // SwiftUI views overlaid on top (VideoControlsOverlay in detail mode).
    // Without this, the NSView can steal hover tracking from grid items
    // underneath, causing spurious onHover(false) events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Single AVPlayerLayer that lives at the ContentView level.
/// Never destroyed during hover→detail→grid transitions — only repositioned.
private struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer
    var showGradient: Bool = false

    func makeNSView(context: Context) -> VideoHostView {
        let view = VideoHostView(player: player)
        view.showGradient = showGradient
        return view
    }

    func updateNSView(_ nsView: VideoHostView, context: Context) {
        nsView.playerLayer.player = player
        nsView.showGradient = showGradient
    }
}

// MARK: - Floating Video Layer

/// A single floating video view placed at the ContentView ZStack level.
/// Moves between grid cell position (hover) and detail position (expanded).
/// No view swap ever occurs — one AVPlayerLayer, animated between frames.
struct FloatingVideoLayer: View {
    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState

    var body: some View {
        if videoPreview.displayState != .hidden, let player = videoPreview.player {
            VideoPlayerNSView(player: player, showGradient: videoPreview.displayState == .grid)
                // Pattern pills overlay — .ultraThinMaterial creates an NSVisualEffectView
                // that composites correctly above the NSView-backed video layer.
                // The gradient scrim is a CAGradientLayer inside VideoHostView for the
                // same reason — plain SwiftUI views can't render above NSViewRepresentable.
                .overlay {
                    if videoPreview.displayState == .grid, !videoPreview.gridPatternNames.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                FlowLayout(spacing: 5) {
                                    ForEach(videoPreview.gridPatternNames, id: \.self) { name in
                                        PatternPill(name: name)
                                    }
                                }
                                Spacer()
                            }
                            .padding(8)
                        }
                        .allowsHitTesting(false)
                    }
                }
                // Controls overlay — only in detail mode
                .overlay {
                    if videoPreview.displayState == .detail {
                        VideoControlsOverlay(player: player)
                    }
                }
                // Drag-to-export — only in detail mode
                .onDrag {
                    appState.isDraggingFromApp = true
                    guard videoPreview.displayState == .detail,
                          let url = videoPreview.activeItemURL else {
                        return NSItemProvider()
                    }
                    let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
                    if let name = videoPreview.activeItemSuggestedName {
                        let ext = url.pathExtension
                        provider.suggestedName = ext.isEmpty ? name : "\(name).\(ext)"
                    }
                    return provider
                } preview: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 64)
                        .background(Color.gray.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(0.85)
                }
            .frame(width: videoPreview.currentFrame.width, height: videoPreview.currentFrame.height)
            .clipShape(RoundedRectangle(cornerRadius: videoPreview.cornerRadius))
            .position(x: videoPreview.currentFrame.midX, y: videoPreview.currentFrame.midY)
            .allowsHitTesting(videoPreview.displayState == .detail)
            .ignoresSafeArea()
        }
    }
}

// MARK: - Video Controls Overlay

/// Minimal controls (play/pause, time) shown on hover in detail mode.
struct VideoControlsOverlay: View {
    let player: AVPlayer

    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showControls = false
    @State private var timeObserver: Any?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if showControls {
                controlsContent
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            if hovering {
                withAnimation(.easeIn(duration: 0.15)) { showControls = true }
                scheduleHide()
            } else {
                hideTask?.cancel()
                withAnimation(.easeOut(duration: 0.3)) { showControls = false }
            }
        }
        .onTapGesture {
            togglePlayback()
            withAnimation(.easeIn(duration: 0.15)) { showControls = true }
            scheduleHide()
        }
        .onAppear { addTimeObserver() }
        .onDisappear { removeTimeObserver() }
    }

    @ViewBuilder
    private var controlsContent: some View {
        // Center play/pause button
        Button(action: togglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)

        // Bottom time bar
        VStack {
            Spacer()
            HStack {
                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            .padding(8)
        }
    }

    private func togglePlayback() {
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            isPlaying = player.rate > 0
            if let item = player.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite { duration = dur }
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        hideTask?.cancel()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showControls = false }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
