import SwiftUI

struct MasonryGrid: View {
    let items: [SnapGridItem]

    private let columns = 2
    private let spacing: CGFloat = 8

    var body: some View {
        let screenWidth = UIScreen.main.bounds.width - 24 // 12pt padding on each side
        let columnWidth = (screenWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(itemsForColumn(column)) { item in
                        NavigationLink(value: item) {
                            GridItemView(item: item, width: columnWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: SnapGridItem.self) { item in
            ImageDetailView(item: item)
        }
    }

    /// Distribute items across columns using shortest-column-first algorithm
    private func itemsForColumn(_ column: Int) -> [SnapGridItem] {
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var columnItems = Array(repeating: [SnapGridItem](), count: columns)

        for item in items {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columnItems[shortest].append(item)
            let estimatedHeight = 1.0 / item.aspectRatio
            columnHeights[shortest] += estimatedHeight + spacing
        }

        return columnItems[column]
    }
}
