import Foundation
import Sparkle
import Combine

/// Thin wrapper around Sparkle's SPUStandardUpdaterController for SwiftUI integration.
/// Bridges Sparkle's KVO-based `canCheckForUpdates` into Combine for use in menu items.
@MainActor
final class UpdaterService: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init() {
        #if DEBUG
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #else
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif

        // Bridge KVO → Combine → @Published
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    var updater: SPUUpdater {
        controller.updater
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
