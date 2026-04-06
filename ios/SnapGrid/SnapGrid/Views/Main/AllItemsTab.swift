import SwiftUI

struct AllItemsTab<AddMenu: View>: View {
    let items: [MediaItem]
    let spaces: [Space]
    let gridWidth: CGFloat
    let isLoading: Bool
    let error: String?
    let selectedItemId: String?
    let showOverlay: Bool
    let onItemSelected: (MediaItem, CGRect, UIImage?) -> Void
    let onRetryAnalysis: (MediaItem) -> Void
    let onShareItem: (MediaItem) -> Void
    let onDeleteItem: (MediaItem) -> Void
    let onAssignToSpace: (String, String?) -> Void
    let onLoadContent: () async -> Void
    let addImagesMenu: AddMenu

    var body: some View {
        NavigationStack {
            ZStack {
                Color.snapDarkBackground
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                } else if let error {
                    ErrorStateView(message: error) {
                        await onLoadContent()
                    }
                } else if items.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        MasonryGrid(
                            items: items,
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
                    .refreshable {
                        await onLoadContent()
                    }
                }
            }
            .navigationTitle("All media")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    addImagesMenu
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
