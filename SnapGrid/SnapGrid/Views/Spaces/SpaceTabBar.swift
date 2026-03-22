import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab Frame Preference Key

private struct TabFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct SpaceTabBar: View {
    let spaces: [Space]
    let activeSpaceId: String?
    @Binding var pendingEditSpaceId: String?
    let onSelectSpace: (String?) -> Void
    let onCreateSpace: () -> Void
    let onDeleteSpace: (String) -> Void
    let onRenameSpace: (String, String) -> Void
    let onReorderSpaces: (Int, Int) -> Void
    let onAssignToSpace: (Set<String>, String?) -> Void

    @State private var editingSpaceId: String?
    @State private var editName: String = ""
    @State private var dropTargetId: String?
    @FocusState private var isEditingFocused: Bool
    @Namespace private var tabNamespace

    // Drag-to-reorder state
    @State private var draggingSpaceId: String?
    @State private var dragOffset: CGFloat = 0
    @State private var targetIndex: Int?
    @State private var tabFrames: [String: CGRect] = [:]

    // Snapshotted at drag start (mirrors Electron's reorderDragRef)
    @State private var dragOriginalIndex: Int = 0
    @State private var dragSnapshotMidpoints: [CGFloat] = []
    @State private var dragSnapshotWidth: CGFloat = 0
    @State private var didDrag: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // "All" tab
                tabView(id: nil, title: "All", isActive: activeSpaceId == nil)
                    .onDrop(of: [.plainText], isTargeted: allTabTargeted) { providers in
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
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .coordinateSpace(name: "tabBar")
            .onPreferenceChange(TabFrameKey.self) { tabFrames = $0 }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
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

    // MARK: - Space Tab

    @ViewBuilder
    private func spaceTab(space: Space, index: Int) -> some View {
        if editingSpaceId == space.id {
            TextField("Name", text: $editName, onCommit: {
                onRenameSpace(space.id, editName)
                editingSpaceId = nil
            })
            .focused($isEditingFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.snapMuted)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 120)
            .onExitCommand { editingSpaceId = nil }
            .onAppear { isEditingFocused = true }
        } else {
            let isDragging = draggingSpaceId == space.id
            let xOffset = isDragging ? dragOffset : shiftOffset(for: index)

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
                .onDrop(of: [.plainText], isTargeted: Binding(
                    get: { dropTargetId == space.id },
                    set: { dropTargetId = $0 ? space.id : nil }
                )) { providers in
                    handleDrop(providers, spaceId: space.id)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TabFrameKey.self,
                            value: [space.id: geo.frame(in: .named("tabBar"))]
                        )
                    }
                )
                .offset(x: xOffset)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .shadow(color: .black.opacity(isDragging ? 0.12 : 0), radius: 8, y: 4)
                .zIndex(isDragging ? 10 : 0)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .named("tabBar"))
                        .onChanged { value in
                            if draggingSpaceId == nil {
                                // Snapshot all tab positions at drag start
                                draggingSpaceId = space.id
                                dragOriginalIndex = index
                                dragSnapshotMidpoints = spaces.compactMap { tabFrames[$0.id]?.midX }
                                dragSnapshotWidth = tabFrames[space.id]?.width ?? 0
                            }
                            dragOffset = value.translation.width

                            // Determine target from cursor vs snapshotted midpoints
                            let cursorX = value.location.x
                            var newTarget = 0
                            for (i, midX) in dragSnapshotMidpoints.enumerated() {
                                if cursorX >= midX {
                                    newTarget = i
                                }
                            }
                            if newTarget != targetIndex {
                                withAnimation(SnapSpring.standard) {
                                    targetIndex = newTarget
                                }
                            }
                        }
                        .onEnded { _ in
                            didDrag = true
                            if let target = targetIndex, target != dragOriginalIndex {
                                onReorderSpaces(dragOriginalIndex, target)
                                draggingSpaceId = nil
                                dragOffset = 0
                                targetIndex = nil
                            } else {
                                withAnimation(SnapSpring.fast) {
                                    draggingSpaceId = nil
                                    dragOffset = 0
                                    targetIndex = nil
                                }
                            }
                        }
                )
        }
    }

    // MARK: - Reorder Shift Computation

    private func shiftOffset(for index: Int) -> CGFloat {
        guard draggingSpaceId != nil,
              let target = targetIndex else { return 0 }

        let draggedIndex = dragOriginalIndex
        if index == draggedIndex { return 0 }

        let shiftAmount = dragSnapshotWidth + 4 // 4 = HStack spacing

        if draggedIndex < target {
            // Moving right: tabs between draggedIndex+1..target shift left
            if index > draggedIndex && index <= target {
                return -shiftAmount
            }
        } else if draggedIndex > target {
            // Moving left: tabs between target..draggedIndex-1 shift right
            if index >= target && index < draggedIndex {
                return shiftAmount
            }
        }
        return 0
    }

    // MARK: - Tab View

    @ViewBuilder
    private func tabView(id: String?, title: String, isActive: Bool) -> some View {
        let isDropTarget = (id == nil && dropTargetId == "ALL") || (id != nil && dropTargetId == id)

        Button {
            if didDrag { didDrag = false; return }
            onSelectSpace(id)
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(
                        isActive ? Color.snapForeground :
                        isDropTarget ? Color.snapForeground.opacity(0.7) :
                        Color.snapMutedForeground
                    )
                    .padding(.horizontal, 8)
                    .padding(.top, 7)
                    .padding(.bottom, 16)

                // Bottom bar indicator
                if isActive {
                    Rectangle()
                        .fill(Color.snapForeground)
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
                        .fill(Color.snapMuted.opacity(0.5))
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
                Task { @MainActor in
                    if text.hasPrefix("snapgrid:") {
                        let idsString = String(text.dropFirst("snapgrid:".count))
                        let itemIds = Set(idsString.split(separator: ",").map(String.init))
                        if !itemIds.isEmpty {
                            onAssignToSpace(itemIds, spaceId)
                        }
                    }
                }
            }
        }
        return true
    }
}
