import SwiftUI

enum AppTab: Hashable {
    case all
    case spaces
    case search
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .all
    var selectedIndex: Int?
    var selectedItemId: String?
    var sourceRect: CGRect = .zero
    var thumbnailImage: UIImage?
    var showOverlay = false
    var activeSpaceId: String? = nil
    var searchText = ""
    var searchScores: [String: Double] = [:]
    var showPhotosPicker = false
    var showFilesPicker = false
    var isImporting = false
    var itemToDelete: MediaItem?
    var shareItem: URL?
}
