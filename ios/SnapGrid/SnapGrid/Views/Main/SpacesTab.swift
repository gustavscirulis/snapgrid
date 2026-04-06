import SwiftUI

struct SpacesTab<AddMenu: View>: View {
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
    let onLoadContent: () async -> Void
    let addImagesMenu: AddMenu

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
                    PlaceholderView(icon: "folder", title: "No spaces yet", subtitle: "Spaces are created in the Mac app")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(spaces) { space in
                                NavigationLink(value: space.id) {
                                    SpaceCardView(space: space)
                                }
                                .buttonStyle(.plain)
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
                    addImagesMenu
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { spaceId in
                SpaceDetailView(
                    spaceId: spaceId,
                    spaces: spaces,
                    allItems: allItems,
                    selectedItemId: selectedItemId,
                    showOverlay: showOverlay,
                    setActiveSpaceId: setActiveSpaceId,
                    onItemSelected: onItemSelected,
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
