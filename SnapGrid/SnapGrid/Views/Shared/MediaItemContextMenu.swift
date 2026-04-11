import SwiftUI

/// Shared context menu for media items, used by both GridItemView and HeroDetailOverlay.
struct MediaItemContextMenu: View {
    let spaces: [Space]
    let activeSpaceId: String?
    let currentSpaceIds: [String]
    var bulkCount: Int? = nil
    let onToggleSpace: (String) -> Void
    let onRemoveFromActiveSpace: (() -> Void)?
    let onShare: () -> Void
    let onRedoAnalysis: () -> Void
    let onDelete: () -> Void

    private var isBulk: Bool { (bulkCount ?? 0) > 1 }
    private var count: Int { bulkCount ?? 1 }

    var body: some View {
        if !spaces.isEmpty {
            Menu {
                ForEach(spaces) { space in
                    Button {
                        onToggleSpace(space.id)
                    } label: {
                        if currentSpaceIds.contains(space.id) {
                            Label(space.name, systemImage: "checkmark")
                        } else {
                            Text(space.name)
                        }
                    }
                }
            } label: {
                Label(isBulk ? "Update \(count) Items in Spaces" : "Update Spaces", systemImage: "folder")
            }

            if activeSpaceId != nil, let onRemoveFromActiveSpace {
                Button {
                    onRemoveFromActiveSpace()
                } label: {
                    Label(isBulk ? "Remove \(count) from Current Space" : "Remove from Current Space", systemImage: "folder.badge.minus")
                }
            }

            Divider()
        }

        Button {
            onShare()
        } label: {
            Label("Share...", systemImage: "square.and.arrow.up")
        }

        Button {
            onRedoAnalysis()
        } label: {
            Label(isBulk ? "Redo Analysis for \(count) Items" : "Redo Analysis", systemImage: "arrow.clockwise")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(isBulk ? "Delete \(count) Items" : "Delete", systemImage: "trash")
        }
    }
}
