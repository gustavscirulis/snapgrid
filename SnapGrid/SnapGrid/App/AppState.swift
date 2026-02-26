import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {
    var selectedIds: Set<String> = []
    var activeSpaceId: String?
    var searchText: String = ""
    var thumbnailSize: ThumbnailSize = .medium
    var detailItem: String? = nil  // MediaItem id
    var isSettingsOpen: Bool = false

    // Undo stack
    private(set) var deletedBatches: [[(id: String, filename: String)]] = []

    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func selectAll(_ ids: [String]) {
        selectedIds = Set(ids)
    }

    func clearSelection() {
        selectedIds.removeAll()
    }

    func pushDeleteBatch(_ items: [(id: String, filename: String)]) {
        deletedBatches.append(items)
    }

    func popDeleteBatch() -> [(id: String, filename: String)]? {
        deletedBatches.popLast()
    }
}

enum ThumbnailSize: String, CaseIterable {
    case small, medium, large, extraLarge

    var columnWidth: CGFloat {
        switch self {
        case .small: return 150
        case .medium: return 220
        case .large: return 320
        case .extraLarge: return 450
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}
