import SwiftUI

@Observable
@MainActor
final class AppState {
    var selectedIndex: Int?
    var selectedItemId: String?
    var sourceRect: CGRect = .zero
    var thumbnailImage: UIImage?
    var showOverlay = false
    var activeSpaceId: String? = nil
    var searchText = ""
    var isSearchActive = false
    var searchScores: [String: Double] = [:]
    var currentPage: Int? = 0
    var showPhotosPicker = false
    var showFilesPicker = false
    var isImporting = false
    var itemToDelete: MediaItem?
    var shareItem: URL?
}
