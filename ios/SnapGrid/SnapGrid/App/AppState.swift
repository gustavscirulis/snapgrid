import SwiftUI

enum AppTab: Hashable {
    case all
    case spaces
    case search
}

enum DetailHost: Equatable {
    case all
    case search
    case space(String)
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .all
    var detailHost: DetailHost?
    var selectedIndex: Int?
    var selectedItemId: String?
    var sourceRect: CGRect = .zero
    var thumbnailImage: UIImage?
    var showOverlay = false
    var pendingSearchActivation = false
    var activeSpaceId: String? = nil
    var searchText = ""
    var searchScores: [String: Double] = [:]
    var showPhotosPicker = false
    var showFilesPicker = false
    var isImporting = false
    var itemToDelete: MediaItem?
    var shareItem: URL?
}
