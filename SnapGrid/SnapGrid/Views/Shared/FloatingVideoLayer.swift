import AVFoundation
import SwiftUI

// MARK: - The ONE AVPlayerLayer

/// NSView subclass that owns a single AVPlayerLayer and keeps it sized
/// to bounds on every layout pass. Uses .resizeAspect so the video is
/// never cropped — the frame is always sized to match the video's aspect
/// ratio, so .resizeAspect fills identically to .resizeAspectFill
/// without amplifying tiny aspect-ratio mismatches.
class VideoHostView: NSView {
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
    // SwiftUI views overlaid on top.
    // Without this, the NSView can steal hover tracking from grid items
    // underneath, causing spurious onHover(false) events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Single AVPlayerLayer that lives at the ContentView level.
/// Used for grid hover video previews only.
/// Reusable NSViewRepresentable wrapping an AVPlayerLayer.
/// Used by both FloatingVideoLayer (grid hover) and DetailItemView (detail playback).
struct VideoPlayerNSView: NSViewRepresentable {
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
/// Shows grid hover video previews — positioned at the hovered grid cell.
struct FloatingVideoLayer: View {
    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            if videoPreview.displayState == .grid, let player = videoPreview.player {
                VideoPlayerNSView(player: player, showGradient: true)
                    // Pattern pills overlay
                    .overlay {
                        if !videoPreview.gridPatternNames.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    FlowLayout(spacing: 4) {
                                        ForEach(videoPreview.gridPatternNames, id: \.self) { name in
                                            PatternPill(name: name, useGlass: false)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(8)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: videoPreview.currentFrame.width, height: videoPreview.currentFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: videoPreview.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: videoPreview.cornerRadius)
                            .strokeBorder(
                                appState.selectedIds.contains(videoPreview.activeItemId ?? "")
                                    ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .position(
                        x: videoPreview.currentFrame.midX - origin.x,
                        y: videoPreview.currentFrame.midY - origin.y
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Video Controls Overlay

/// Minimal controls (play/pause, time) shown on hover over video content.
struct VideoControlsOverlay: View {
    let player: AVPlayer

    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showControls = false
    @State private var timeObserver: Any?
    /// The player instance the time observer was added to — may differ from
    /// `player` if the player was swapped mid-navigation.
    @State private var observedPlayer: AVPlayer?
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
        .onChange(of: ObjectIdentifier(player)) { _, _ in
            addTimeObserver()
        }
    }

    @ViewBuilder
    private var controlsContent: some View {
        // Center play/pause button
        Button(action: togglePlayback) {
            let icon = Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)

            if #available(macOS 26, *) {
                icon.glassEffect(.regular.interactive(), in: .circle)
            } else {
                icon
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")

        // Bottom time bar
        VStack {
            Spacer()
            HStack {
                let timeText = Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                if #available(macOS 26, *) {
                    timeText.glassEffect(.regular, in: .rect(cornerRadius: 4))
                } else {
                    timeText
                        .background(.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
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
        removeTimeObserver()
        observedPlayer = player
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
        if let observer = timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(observer)
            timeObserver = nil
            self.observedPlayer = nil
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
        formatDuration(seconds)
    }
}

/// Shared duration formatting: "m:ss"
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(seconds)
    return "\(total / 60):\(String(format: "%02d", total % 60))"
}
