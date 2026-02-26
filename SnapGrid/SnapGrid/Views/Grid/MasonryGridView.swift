import SwiftUI

struct MasonryGridView: View {
    let items: [MediaItem]
    let thumbnailSize: ThumbnailSize
    let selectedIds: Set<String>
    let onSelect: (String) -> Void
    let onToggleSelect: (String) -> Void
    let onDelete: (Set<String>) -> Void
    let onAssignToSpace: (Set<String>, String?) -> Void

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, Int(geometry.size.width / thumbnailSize.columnWidth))
            let spacing: CGFloat = 12
            let totalSpacing = spacing * CGFloat(columns - 1) + 24 // 12px padding each side
            let columnWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        LazyVStack(spacing: spacing) {
                            ForEach(itemsForColumn(column, totalColumns: columns)) { item in
                                GridItemView(
                                    item: item,
                                    width: columnWidth,
                                    isSelected: selectedIds.contains(item.id),
                                    onSelect: { onSelect(item.id) },
                                    onToggleSelect: { onToggleSelect(item.id) },
                                    onDelete: { onDelete(Set([item.id])) }
                                )
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    /// Distribute items across columns using shortest-column-first algorithm
    private func itemsForColumn(_ column: Int, totalColumns: Int) -> [MediaItem] {
        var columnHeights = Array(repeating: CGFloat(0), count: totalColumns)
        var columnItems = Array(repeating: [MediaItem](), count: totalColumns)

        for item in items {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columnItems[shortest].append(item)
            let estimatedHeight = 1.0 / item.aspectRatio
            columnHeights[shortest] += estimatedHeight + 12
        }

        return columnItems[column]
    }
}
