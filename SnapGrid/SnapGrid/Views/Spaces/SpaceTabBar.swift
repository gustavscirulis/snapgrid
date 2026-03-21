import SwiftUI
import UniformTypeIdentifiers

struct SpaceTabBar: View {
    let spaces: [Space]
    let activeSpaceId: String?
    let onSelectSpace: (String?) -> Void
    let onCreateSpace: () -> Void
    let onDeleteSpace: (String) -> Void
    let onRenameSpace: (String, String) -> Void
    let onReorderSpaces: (Int, Int) -> Void
    let onAssignToSpace: (Set<String>, String?) -> Void

    @State private var editingSpaceId: String?
    @State private var editName: String = ""
    @State private var dropTargetId: String?
    @Namespace private var tabNamespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // "All" tab
                tabView(id: nil, title: "All", isActive: activeSpaceId == nil)
                    .onDrop(of: [.text], isTargeted: allTabTargeted) { providers in
                        handleDrop(providers, spaceId: nil)
                    }

                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    spaceTab(space: space, index: index)
                }

                // Add button
                Button(action: onCreateSpace) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.snapMutedForeground)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)  // SpaceTabBar.tsx — border-gray-200/50 dark:border-zinc-800/50
        }
    }

    // MARK: - Space Tab

    @ViewBuilder
    private func spaceTab(space: Space, index: Int) -> some View {
        if editingSpaceId == space.id {
            TextField("Name", text: $editName, onCommit: {
                onRenameSpace(space.id, editName)
                editingSpaceId = nil
            })
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.snapMuted)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 120)
            .onExitCommand { editingSpaceId = nil }
        } else {
            tabView(id: space.id, title: space.name, isActive: activeSpaceId == space.id)
                .contextMenu {
                    Button("Rename") {
                        editName = space.name
                        editingSpaceId = space.id
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        onDeleteSpace(space.id)
                    }
                }
                .onDoubleClick {
                    editName = space.name
                    editingSpaceId = space.id
                }
                .draggable(space.id) {
                    Text(space.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.snapForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.snapMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let droppedId = items.first else { return false }

                    if let fromIndex = spaces.firstIndex(where: { $0.id == droppedId }) {
                        onReorderSpaces(fromIndex, index)
                        return true
                    }

                    let itemIds = Set(droppedId.split(separator: ",").map(String.init))
                    if !itemIds.isEmpty {
                        onAssignToSpace(itemIds, space.id)
                        return true
                    }

                    return false
                } isTargeted: { targeted in
                    dropTargetId = targeted ? space.id : nil
                }
        }
    }

    // MARK: - Tab View

    // SpaceTabBar.tsx:283,318-319 — bottom bar indicator with gray text colors
    @ViewBuilder
    private func tabView(id: String?, title: String, isActive: Bool) -> some View {
        let isDropTarget = (id == nil && dropTargetId == "ALL") || (id != nil && dropTargetId == id)

        Button {
            onSelectSpace(id)
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(
                        isActive ? Color.snapForeground :       // SpaceTabBar.tsx:318 — text-gray-900/gray-100
                        isDropTarget ? Color.snapForeground.opacity(0.7) :
                        Color.snapMutedForeground               // SpaceTabBar.tsx:319 — text-gray-500/gray-400
                    )
                    .padding(.horizontal, 8)
                    .padding(.top, 7)
                    .padding(.bottom, 16)

                // Bottom bar indicator
                if isActive {
                    Rectangle()
                        .fill(Color.snapForeground)  // SpaceTabBar.tsx:283 — bg-gray-900 dark:bg-gray-100
                        .frame(height: 2)
                        .clipShape(Capsule())
                        .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                        .padding(.horizontal, 6)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                        .padding(.horizontal, 6)
                }
            }
            .contentShape(Rectangle())
            .background {
                if isDropTarget && !isActive {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.snapMuted.opacity(0.5))  // SpaceTabBar.tsx — drop highlight
                }
            }
        }
        .buttonStyle(.plain)
        .animation(SnapSpring.standard, value: activeSpaceId)
    }

    // MARK: - Drop Helpers

    private var allTabTargeted: Binding<Bool> {
        Binding(
            get: { dropTargetId == nil && false },
            set: { dropTargetId = $0 ? "ALL" : nil }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider], spaceId: String?) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                guard let text = string as? String else { return }
                let itemIds = Set(text.split(separator: ",").map(String.init))
                if !itemIds.isEmpty {
                    Task { @MainActor in
                        onAssignToSpace(itemIds, spaceId)
                    }
                }
            }
        }
        return true
    }
}
