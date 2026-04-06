import SwiftUI

/// Content view for the search tab. The search field presentation and
/// keyboard focus are managed by `Tab(role: .search)` automatically.
struct SearchResultsView: View {
    let items: [MediaItem]
    let spaces: [Space]
    let gridWidth: CGFloat
    let selectedItemId: String?
    let showOverlay: Bool
    @Binding var searchText: String
    let onDismiss: () -> Void
    let onItemSelected: (MediaItem, CGRect, UIImage?) -> Void
    let onRetryAnalysis: (MediaItem) -> Void
    let onShareItem: (MediaItem) -> Void
    let onDeleteItem: (MediaItem) -> Void
    let onAssignToSpace: (String, String?) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.snapDarkBackground
                    .ignoresSafeArea()

                if items.isEmpty {
                    PlaceholderView(icon: "magnifyingglass", title: "Search your library", subtitle: "Find patterns, context, and more")
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
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search patterns, context...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        searchText = ""
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}
