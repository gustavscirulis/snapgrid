import SwiftUI

struct SpaceSidebarView: View {
    let spaces: [Space]
    @Binding var selection: SidebarItem
    @Binding var pendingEditSpaceId: String?
    let onCreateSpace: () -> Void
    let onDeleteSpace: (String) -> Void
    let onRenameSpace: (String, String) -> Void
    let onReorderSpaces: (Int, Int) -> Void
    let onAssignToSpace: (Set<String>, String?) -> Void

    @State private var editingSpaceId: String?
    @State private var editName: String = ""
    @State private var spaceToDelete: Space?
    @State private var dropTargetId: String?
    @FocusState private var isEditingFocused: Bool

    var body: some View {
        List(selection: $selection) {
            Text("All")
                .tag(SidebarItem.all)
                .listItemTint(.primary)
                .dropDestination(for: String.self) { strings, _ in
                    handleDropStrings(strings, spaceId: nil)
                } isTargeted: { targeted in
                    dropTargetId = targeted ? "ALL" : nil
                }

            Section("Spaces") {
                ForEach(spaces) { space in
                    spaceRow(space)
                        .tag(SidebarItem.space(space.id))
                }
                .onMove { source, destination in
                    guard let fromIndex = source.first else { return }
                    let toIndex = destination > fromIndex ? destination - 1 : destination
                    onReorderSpaces(fromIndex, toIndex)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) {
            Button(action: onCreateSpace) {
                Label("New Space", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .alert("Delete Space?", isPresented: Binding(
            get: { spaceToDelete != nil },
            set: { if !$0 { spaceToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                spaceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let space = spaceToDelete {
                    onDeleteSpace(space.id)
                    spaceToDelete = nil
                }
            }
        } message: {
            if let space = spaceToDelete {
                Text("\"\(space.name)\" contains \(space.items.count) item\(space.items.count == 1 ? "" : "s"). They won't be deleted, but will be unassigned from this space.")
            }
        }
        .onChange(of: pendingEditSpaceId) { _, newValue in
            if let spaceId = newValue,
               let space = spaces.first(where: { $0.id == spaceId }) {
                editName = space.name
                editingSpaceId = spaceId
                pendingEditSpaceId = nil
                isEditingFocused = true
            }
        }
    }

    // MARK: - Space Row

    @ViewBuilder
    private func spaceRow(_ space: Space) -> some View {
        if editingSpaceId == space.id {
            TextField("Name", text: $editName, onCommit: {
                onRenameSpace(space.id, editName)
                editingSpaceId = nil
            })
            .focused($isEditingFocused)
            .onExitCommand { editingSpaceId = nil }
            .onAppear { isEditingFocused = true }
        } else {
            Text(space.name)
                .contextMenu {
                    Button("Rename") {
                        editName = space.name
                        editingSpaceId = space.id
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        if space.items.isEmpty {
                            onDeleteSpace(space.id)
                        } else {
                            spaceToDelete = space
                        }
                    }
                }
                .onDoubleClick {
                    editName = space.name
                    editingSpaceId = space.id
                }
                .dropDestination(for: String.self) { strings, _ in
                    handleDropStrings(strings, spaceId: space.id)
                } isTargeted: { targeted in
                    dropTargetId = targeted ? space.id : nil
                }
        }
    }

    // MARK: - Drop Helpers

    private func handleDropStrings(_ strings: [String], spaceId: String?) -> Bool {
        for text in strings {
            if text.hasPrefix("snapgrid:") {
                let idsString = String(text.dropFirst("snapgrid:".count))
                let itemIds = Set(idsString.split(separator: ",").map(String.init))
                if !itemIds.isEmpty {
                    onAssignToSpace(itemIds, spaceId)
                    return true
                }
            }
        }
        return false
    }
}
