import AVFoundation
import SwiftUI

// MARK: - Display State

enum VideoDisplayState: Equatable {
    case hidden
    case grid
}

// MARK: - VideoPreviewManager

/// Manages a single AVPlayer for grid hover video previews.
/// The floating video layer reads `currentFrame`, `cornerRadius`, and `displayState`
/// to position itself. Grid hover only — detail views manage their own players.
@Observable
@MainActor
final class VideoPreviewManager {
    /// The currently active preview player
    private(set) var player: AVPlayer?

    /// The media item ID whose video is currently loaded
    private(set) var activeItemId: String?

    /// Current display mode for the floating video layer
    private(set) var displayState: VideoDisplayState = .hidden

    /// The animated frame for the floating video layer
    var currentFrame: CGRect = .zero

    /// The animated corner radius
    var cornerRadius: CGFloat = 12

    /// The grid cell's live global frame — updated continuously by GridItemView
    private(set) var gridItemFrame: CGRect = .zero

    /// Pattern names to display on the floating layer during grid hover
    private(set) var gridPatternNames: [String] = []

    private var loopObserver: NSObjectProtocol?

    // MARK: - Grid Hover

    /// Start hover preview — creates player, positions floating layer at grid cell
    func startPreview(itemId: String, url: URL, frame: CGRect, patternNames: [String] = []) {
        if activeItemId == itemId, player != nil {
            gridItemFrame = frame
            if displayState == .grid {
                currentFrame = frame
            }
            return
        }

        stopPreview()

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        player = newPlayer
        activeItemId = itemId
        gridItemFrame = frame
        gridPatternNames = patternNames
        currentFrame = frame
        cornerRadius = 12
        displayState = .grid

        addLoopObserver(for: newPlayer)
        newPlayer.play()
    }

    /// Update the grid cell's live frame (scroll, resize)
    func updateGridFrame(_ frame: CGRect) {
        gridItemFrame = frame
        if displayState == .grid {
            currentFrame = frame
        }
    }

    /// Stop hover preview
    func stopPreview() {
        displayState = .hidden
        cleanup()
    }

    // MARK: - Private

    private func cleanup() {
        removeLoopObserver()
        player?.pause()
        player = nil
        activeItemId = nil
        gridPatternNames = []
    }

    private func addLoopObserver(for player: AVPlayer?) {
        removeLoopObserver()
        guard let player else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func removeLoopObserver() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
}
