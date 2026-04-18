import Foundation
import SwiftUI

enum SidebarItem: Hashable {
    case all
    case space(String) // Space.id
}

enum SpaceMembershipAction {
    case toggle(String)
    case add(String)
    case remove(String)
    case clearAll
}

@Observable
@MainActor
final class AppState {
    var selectedIds: Set<String> = []
    var anchorId: String?

    init() {
        // Restore persisted state
        if let saved = UserDefaults.standard.string(forKey: "thumbnailSize"),
           let size = ThumbnailSize(rawValue: saved) {
            thumbnailSize = size
        }
        if let savedId = UserDefaults.standard.string(forKey: "lastActiveSpaceId") {
            sidebarSelection = .space(savedId)
        } else {
            sidebarSelection = .all
        }
    }

    var sidebarSelection: SidebarItem = .all {
        didSet {
            let newId: String? = if case .space(let id) = sidebarSelection { id } else { nil }
            UserDefaults.standard.set(newId, forKey: "lastActiveSpaceId")
        }
    }

    var activeSpaceId: String? {
        if case .space(let id) = sidebarSelection { return id }
        return nil
    }
    var searchText: String = ""
    var thumbnailSize: ThumbnailSize = .medium {
        didSet { UserDefaults.standard.set(thumbnailSize.rawValue, forKey: "thumbnailSize") }
    }
    var detailItem: String? = nil  // MediaItem id
    var detailSourceFrame: CGRect? = nil  // Global frame of tapped thumbnail for hero animation
    var isSettingsOpen: Bool = false
    var isDraggingFromApp: Bool = false

    /// Items currently animating deletion (value 1). Absent entries are normal (stage 0).
    var deletingItemStages: [String: Int] = [:]

    func deleteStage(for id: String) -> Int {
        deletingItemStages[id] ?? 0
    }

    // Unified undo/redo stacks — hold both deletion and space-change snapshots in LIFO order
    private(set) var undoStack: [UndoBatch] = []
    private(set) var redoStack: [UndoBatch] = []

    // Toast notifications
    var toasts: [ToastMessage] = []

    func showToast(_ message: String) {
        let toast = ToastMessage(message: message)
        withAnimation(SnapSpring.standard) {
            toasts.append(toast)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(SnapSpring.fast) {
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

    private let maxUndoBatches = 20

    func pushUndoBatch(_ batch: UndoBatch) {
        undoStack.append(batch)
        if undoStack.count > maxUndoBatches {
            undoStack.removeFirst(undoStack.count - maxUndoBatches)
        }
    }

    func popUndoBatch() -> UndoBatch? {
        undoStack.popLast()
    }

    func pushRedoBatch(_ batch: UndoBatch) {
        redoStack.append(batch)
        if redoStack.count > maxUndoBatches {
            redoStack.removeFirst(redoStack.count - maxUndoBatches)
        }
    }

    func popRedoBatch() -> UndoBatch? {
        redoStack.popLast()
    }

    func clearRedoStack() {
        redoStack.removeAll()
    }

    func pushDeleteBatch(_ items: [DeletedItemInfo]) {
        pushUndoBatch(.deletion(items))
        clearRedoStack()
    }

    func pushSpaceChangeBatch(_ changes: [SpaceChangeInfo]) {
        pushUndoBatch(.spaceChange(changes))
        clearRedoStack()
    }
}

struct DeletedItemInfo {
    let id: String
    let filename: String
    let mediaType: MediaType
    let width: Int
    let height: Int
    let duration: Double?
    let spaceIds: [String]

    // Snapshot of analysis data — stored as plain values, NOT a reference to
    // the SwiftData @Model object, which becomes invalid after deletion.
    let imageContext: String?
    let imageSummary: String?
    let patterns: [PatternTag]?
    let analyzedAt: Date?
    let analysisProvider: String?
    let analysisModel: String?
}

struct SpaceChangeInfo {
    let itemId: String
    let previousSpaceIds: [String]
}

struct DeletedSpaceInfo {
    let id: String
    let name: String
    let order: Int
    let createdAt: Date
    let customPrompt: String?
    let useCustomPrompt: Bool
    let itemIds: [String]
}

enum UndoBatch {
    case deletion([DeletedItemInfo])
    case spaceChange([SpaceChangeInfo])
    case spaceDeletion(DeletedSpaceInfo)
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
            if width >= 1200 { return 6 }
            if width >= 1000 { return 5 }
            if width >= 800  { return 4 }
            if width >= 480  { return 3 }
            return 2
        case .medium:
            if width >= 1200 { return 4 }
            if width >= 900  { return 3 }
            if width >= 500  { return 2 }
            return 1
        case .large:
            if width >= 1100 { return 3 }
            if width >= 600  { return 2 }
            return 1
        case .extraLarge:
            if width >= 700  { return 2 }
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
