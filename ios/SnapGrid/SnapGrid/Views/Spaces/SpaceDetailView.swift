import SwiftUI

struct SpaceDetailView<AddMenu: View>: View {
    let spaceId: String
    let spaces: [Space]
    let allItems: [MediaItem]
    let selectedItemId: String?
    let showOverlay: Bool
    let setActiveSpaceId: (String?) -> Void
    let onItemSelected: (MediaItem, CGRect, UIImage?) -> Void
    let onRetryAnalysis: (MediaItem) -> Void
    let onShareItem: (MediaItem) -> Void
    let onDeleteItem: (MediaItem) -> Void
    let onAssignToSpace: (String, String?) -> Void
    let addImagesMenu: AddMenu

    private var space: Space? {
        spaces.first { $0.id == spaceId }
    }

    private var spaceItems: [MediaItem] {
        allItems.filter { $0.space?.id == spaceId }
    }

    var body: some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width - 24

            ZStack {
                Color.snapDarkBackground
                    .ignoresSafeArea()

                if spaceItems.isEmpty {
                    PlaceholderView(icon: "folder", title: "No items in this space", subtitle: "Add items from the All tab")
                } else {
                    ScrollView {
                        MasonryGrid(
                            items: spaceItems,
                            spaces: spaces,
                            availableWidth: gridWidth,
                            selectedItemId: showOverlay ? selectedItemId : nil,
                            onItemSelected: onItemSelected,
                            onRetryAnalysis: onRetryAnalysis,
                            onShareItem: onShareItem,
                            onDeleteItem: onDeleteItem,
                            onAssignToSpace: onAssignToSpace
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 70)
                    }
                }
            }
        }
        .navigationTitle(space?.name ?? "Space")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addImagesMenu
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { setActiveSpaceId(spaceId) }
        .onDisappear { setActiveSpaceId(nil) }
    }
}
