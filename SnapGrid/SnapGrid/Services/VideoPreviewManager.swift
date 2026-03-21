import AVFoundation
import Foundation

@Observable
@MainActor
final class VideoPreviewManager {
    /// The currently active preview player (created on hover, shared with detail overlay)
    private(set) var player: AVPlayer?

    /// The media item ID whose video is currently loaded in the player
    private(set) var activeItemId: String?

    /// Whether the player has been handed off to the detail overlay
    /// (prevents cleanup on hover-end when detail is open)
    var isHandedOffToDetail: Bool = false

    private var loopObserver: NSObjectProtocol?

    /// Start hover preview for a video item
    func startPreview(itemId: String, url: URL) {
        // Already previewing this item — no-op
        if activeItemId == itemId, player != nil { return }

        // Stop any existing preview
        stopPreview()

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        player = newPlayer
        activeItemId = itemId

        // Loop playback for hover preview
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        newPlayer.play()
    }

    /// Stop hover preview (only if not handed off to detail)
    func stopPreview() {
        guard !isHandedOffToDetail else { return }
        cleanup()
    }

    /// Claim the player for the detail overlay — unmutes and prevents cleanup
    func claimForDetail() -> AVPlayer? {
        guard let player else { return nil }
        isHandedOffToDetail = true
        player.isMuted = false
        removeLoopObserver()
        return player
    }

    /// Release the player when detail overlay closes
    func releaseFromDetail() {
        isHandedOffToDetail = false
        cleanup()
    }

    /// Create a fresh player for a different video in the detail overlay (arrow key navigation)
    func switchDetailPlayer(itemId: String, url: URL) -> AVPlayer {
        cleanup()
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = false
        player = newPlayer
        activeItemId = itemId
        isHandedOffToDetail = true
        newPlayer.play()
        return newPlayer
    }

    // MARK: - Private

    private func cleanup() {
        removeLoopObserver()
        player?.pause()
        player = nil
        activeItemId = nil
    }

    private func removeLoopObserver() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
}
