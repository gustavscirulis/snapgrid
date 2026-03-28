import AVFoundation
import SwiftUI

// MARK: - Display State

enum VideoDisplayState: Equatable {
    case hidden
    case grid
    case detail
}

// MARK: - VideoPreviewManager

/// Manages a single AVPlayer and the floating video layer's display frame.
/// The floating video layer reads `currentFrame`, `cornerRadius`, and `displayState`
/// to position itself. No view swap ever occurs — one player, one layer, repositioned.
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

    /// The animated corner radius (12 for grid, 16 for detail)
    var cornerRadius: CGFloat = 12

    /// The grid cell's live global frame — updated continuously by GridItemView
    private(set) var gridItemFrame: CGRect = .zero

    /// Pattern names to display on the floating layer during grid hover
    private(set) var gridPatternNames: [String] = []

    /// File URL of the active video (set during detail mode for drag-to-export)
    private(set) var activeItemURL: URL?

    /// Suggested export name for the active video (from AI analysis)
    private(set) var activeItemSuggestedName: String?

    private var isHandedOffToDetail = false
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

    /// Stop hover preview (blocked while handed off to detail)
    func stopPreview() {
        guard !isHandedOffToDetail else { return }
        displayState = .hidden
        cleanup()
    }

    // MARK: - Detail Transition

    /// Pre-claim the player for detail (called synchronously in click handler).
    /// Prevents onHover(false) from destroying the player when overlay appears.
    func claimForDetail() {
        guard player != nil else { return }
        isHandedOffToDetail = true
        player?.isMuted = false
        removeLoopObserver()
    }

    /// Transition to detail mode. Sets properties — caller wraps in withAnimation.
    /// If no hover preview exists, creates a fresh player at finalFrame (no animation needed).
    func transitionToDetail(itemId: String, url: URL, finalFrame: CGRect, suggestedName: String? = nil) {
        if player == nil || activeItemId != itemId {
            // No hover preview — create fresh player directly at detail position
            cleanup()
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = false
            player = newPlayer
            activeItemId = itemId
            isHandedOffToDetail = true
            displayState = .detail
            currentFrame = finalFrame
            cornerRadius = 16
            newPlayer.play()
        } else {
            // Hover preview exists — just update state. Frame change animates.
            displayState = .detail
            currentFrame = finalFrame
            cornerRadius = 16
        }

        activeItemURL = url
        activeItemSuggestedName = suggestedName
    }

    /// Update the detail frame on window resize
    func updateDetailFrame(_ frame: CGRect) {
        if displayState == .detail {
            currentFrame = frame
        }
    }

    /// Animate back to grid position. Sets properties — caller wraps in withAnimation.
    func transitionToGrid() {
        player?.isMuted = true
        addLoopObserver(for: player)
        currentFrame = gridItemFrame
        cornerRadius = 12
    }

    /// Called when close animation completes and overlay is removed
    func completeTransitionToGrid() {
        displayState = .grid
        // Delay clearing handoff — the overlay removal triggers a transient
        // onHover(false) on the grid item; keep the flag true so stopPreview() is a no-op
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            isHandedOffToDetail = false
        }
    }

    /// Create a fresh player for arrow key navigation in detail
    func switchDetailPlayer(itemId: String, url: URL, frame: CGRect, suggestedName: String? = nil) {
        cleanup()
        activeItemURL = url
        activeItemSuggestedName = suggestedName
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = false
        player = newPlayer
        activeItemId = itemId
        isHandedOffToDetail = true
        currentFrame = frame
        cornerRadius = 16
        displayState = .detail
        newPlayer.play()
    }

    // MARK: - Private

    private func cleanup() {
        removeLoopObserver()
        player?.pause()
        player = nil
        activeItemId = nil
        activeItemURL = nil
        activeItemSuggestedName = nil
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
