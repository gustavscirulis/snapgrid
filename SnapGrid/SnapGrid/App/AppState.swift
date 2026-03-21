import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {
    var selectedIds: Set<String> = []
    var anchorId: String?
    var activeSpaceId: String?
    var searchText: String = ""
    var thumbnailSize: ThumbnailSize = .medium
    var detailItem: String? = nil  // MediaItem id
    var isSettingsOpen: Bool = false

    // Undo stack — stores enough info to fully restore deleted items
    private(set) var deletedBatches: [[DeletedItemInfo]] = []

    // Toast notifications
    var toasts: [ToastMessage] = []

    func showToast(_ message: String) {
        let toast = ToastMessage(message: message)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toasts.append(toast)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.2)) {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }

    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        anchorId = id
    }

    func rangeSelect(targetId: String, orderedIds: [String]) {
        guard let anchor = anchorId else {
            selectedIds = [targetId]
            return
        }

        guard let anchorIndex = orderedIds.firstIndex(of: anchor),
              let targetIndex = orderedIds.firstIndex(of: targetId) else {
            selectedIds = [targetId]
            return
        }

        let start = min(anchorIndex, targetIndex)
        let end = max(anchorIndex, targetIndex)
        let rangeIds = orderedIds[start...end]
        selectedIds.formUnion(rangeIds)
        // Anchor stays — don't update on range select
    }

    func selectAll(_ ids: [String]) {
        selectedIds = Set(ids)
        if let first = ids.first {
            anchorId = first
        }
    }

    func clearSelection() {
        selectedIds.removeAll()
        anchorId = nil
    }

    // MARK: - Thumbnail Zoom

    func zoomIn() {
        guard let index = ThumbnailSize.allCases.firstIndex(of: thumbnailSize),
              index < ThumbnailSize.allCases.count - 1 else { return }
        thumbnailSize = ThumbnailSize.allCases[index + 1]
    }

    func zoomOut() {
        guard let index = ThumbnailSize.allCases.firstIndex(of: thumbnailSize),
              index > 0 else { return }
        thumbnailSize = ThumbnailSize.allCases[index - 1]
    }

    // MARK: - Undo Stack

    func pushDeleteBatch(_ items: [DeletedItemInfo]) {
        deletedBatches.append(items)
    }

    func popDeleteBatch() -> [DeletedItemInfo]? {
        deletedBatches.popLast()
    }
}

struct DeletedItemInfo {
    let id: String
    let filename: String
    let mediaType: MediaType
    let width: Int
    let height: Int
    let duration: Double?
    let analysisResult: AnalysisResult?
    let spaceId: String?
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
}

enum ThumbnailSize: String, CaseIterable {
    case small, medium, large, extraLarge

    func columns(forWidth width: CGFloat) -> Int {
        switch self {
        case .small:
            if width >= 1536 { return 6 }
            if width >= 1280 { return 5 }
            if width >= 1024 { return 4 }
            if width >= 640  { return 3 }
            return 2
        case .medium:
            if width >= 1536 { return 4 }
            if width >= 1280 { return 3 }
            if width >= 1024 { return 2 }
            return 1
        case .large:
            if width >= 1536 { return 3 }
            if width >= 1280 { return 2 }
            if width >= 1024 { return 2 }
            return 1
        case .extraLarge:
            if width >= 1280 { return 2 }
            return 1
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
