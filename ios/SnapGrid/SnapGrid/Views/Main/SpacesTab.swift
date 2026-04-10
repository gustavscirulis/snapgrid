import SwiftUI

struct SpacesTab<AddMenu: View>: View {
    let spaces: [Space]
    let allItems: [MediaItem]
    let selectedItemId: String?
    let showOverlay: Bool
    let setActiveSpaceId: (String?) -> Void
    let onItemSelected: (MediaItem, CGRect, UIImage?, DetailHost) -> Void
    let onRetryAnalysis: (MediaItem) -> Void
    let onShareItem: (MediaItem) -> Void
    let onDeleteItem: (MediaItem) -> Void
    let onAssignToSpace: (String, String?) -> Void
    let onLoadContent: () async -> Void
    let onCreateSpace: () -> Void
    let onRenameSpace: (String) -> Void
    let onDeleteSpace: (String) -> Void
    let addImagesMenu: AddMenu

    @State private var spaceToDelete: Space?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.snapDarkBackground
                    .ignoresSafeArea()

                if spaces.isEmpty {
                    PlaceholderView(icon: "folder", title: "No spaces yet", subtitle: "Tap the folder icon to create a space")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(spaces) { space in
                                NavigationLink(value: space.id) {
                                    SpaceCardView(space: space)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        onRenameSpace(space.id)
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        if space.items.isEmpty {
                                            onDeleteSpace(space.id)
                                        } else {
                                            spaceToDelete = space
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 70)
                    }
                    .refreshable {
                        await onLoadContent()
                    }
                }
            }
            .navigationTitle("Spaces")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onCreateSpace) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .navigationDestination(for: String.self) { spaceId in
                SpaceDetailView(
                    spaceId: spaceId,
                    spaces: spaces,
                    allItems: allItems,
                    selectedItemId: selectedItemId,
                    showOverlay: showOverlay,
                    setActiveSpaceId: setActiveSpaceId,
                    onItemSelected: { item, rect, thumbnail in
                        onItemSelected(item, rect, thumbnail, .space(spaceId))
                    },
                    onRetryAnalysis: onRetryAnalysis,
                    onShareItem: onShareItem,
                    onDeleteItem: onDeleteItem,
                    onAssignToSpace: onAssignToSpace,
                    addImagesMenu: addImagesMenu
                )
            }
        }
    }
}
