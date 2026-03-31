import SwiftUI

struct MasonryGrid: View {
    let items: [MediaItem]
    let availableWidth: CGFloat
    var selectedItemId: String?
    var onItemSelected: ((MediaItem, CGRect, UIImage?) -> Void)?
    var onRetryAnalysis: ((MediaItem) -> Void)?
    var onShareItem: ((MediaItem) -> Void)?
    var onDeleteItem: ((MediaItem) -> Void)?

    private let columns = 2
    private let spacing: CGFloat = 8

    /// Distribute items across columns using shortest-column-first algorithm (computed once per body)
    private var columnAssignments: [[MediaItem]] {
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var columnItems = Array(repeating: [MediaItem](), count: columns)

        for item in items {
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columnItems[shortest].append(item)
            let estimatedHeight = 1.0 / item.gridAspectRatio
            columnHeights[shortest] += estimatedHeight + spacing
        }

        return columnItems
    }

    var body: some View {
        let columnWidth = (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let assignments = columnAssignments

        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(assignments[column]) { item in
                        GridItemView(
                            item: item,
                            width: columnWidth,
                            isSelected: selectedItemId == item.id,
                            onSelect: onItemSelected,
                            onRetryAnalysis: onRetryAnalysis.map { callback in
                                { callback(item) }
                            },
                            onShare: onShareItem.map { callback in
                                { callback(item) }
                            },
                            onDelete: onDeleteItem.map { callback in
                                { callback(item) }
                            }
                        )
                    }
                }
            }
        }
    }
}
