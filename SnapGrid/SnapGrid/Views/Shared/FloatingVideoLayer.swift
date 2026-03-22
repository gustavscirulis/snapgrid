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

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Single AVPlayerLayer that lives at the ContentView level.
/// Never destroyed during hover→detail→grid transitions — only repositioned.
private struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> VideoHostView {
        VideoHostView(player: player)
    }

    func updateNSView(_ nsView: VideoHostView, context: Context) {
        nsView.playerLayer.player = player
    }
}

// MARK: - Floating Video Layer

/// A single floating video view placed at the ContentView ZStack level.
/// Moves between grid cell position (hover) and detail position (expanded).
/// No view swap ever occurs — one AVPlayerLayer, animated between frames.
struct FloatingVideoLayer: View {
    @Environment(VideoPreviewManager.self) private var videoPreview

    var body: some View {
        if videoPreview.displayState != .hidden, let player = videoPreview.player {
            ZStack {
                VideoPlayerNSView(player: player)

                // Controls overlay — only in detail mode
                if videoPreview.displayState == .detail {
                    VideoControlsOverlay(player: player)
                }
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
