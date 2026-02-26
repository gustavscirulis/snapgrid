import SwiftUI

struct SpaceTabBar: View {
    let spaces: [Space]
    @Binding var activeSpaceId: String?
    let onCreateSpace: () -> Void
    let onDeleteSpace: (String) -> Void
    let onRenameSpace: (String, String) -> Void

    @State private var editingSpaceId: String?
    @State private var editName: String = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // "All" tab
                TabButton(
                    title: "All",
                    isActive: activeSpaceId == nil,
                    action: { activeSpaceId = nil }
                )

                ForEach(spaces) { space in
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
                        TabButton(
                            title: space.name,
                            isActive: activeSpaceId == space.id,
                            action: { activeSpaceId = space.id }
                        )
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
                        .onTapGesture(count: 2) {
                            editName = space.name
                            editingSpaceId = space.id
                        }
                    }
                }

                // Add button
                Button(action: onCreateSpace) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? Color.white.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
