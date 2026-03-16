import SwiftUI

struct MasonryGridView: View {
    let items: [MediaItem]
    let thumbnailSize: ThumbnailSize
    let selectedIds: Set<String>
    let spaces: [Space]
    let activeSpaceId: String?
    let onSelect: (String) -> Void
    let onToggleSelect: (String) -> Void
    let onShiftSelect: (String) -> Void
    let onDelete: (Set<String>) -> Void
    let onAssignToSpace: (Set<String>, String?) -> Void
    let onRetryAnalysis: (MediaItem) -> Void
    let onSetSelection: (Set<String>) -> Void

    // Rubber band state
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var rubberBandStart: CGPoint?
    @State private var rubberBandCurrent: CGPoint?
    @State private var rubberBandActive = false
    @State private var frozenSelection: Set<String> = []

    private var rubberBandRect: CGRect? {
        guard let start = rubberBandStart, let current = rubberBandCurrent, rubberBandActive else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, Int(geometry.size.width / thumbnailSize.columnWidth))
            let spacing: CGFloat = 16  // masonry-grid.css:10,16 — 16px column/row gaps
            let totalSpacing = spacing * CGFloat(columns - 1) + 32 // 16px padding each side
            let columnWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Background gesture layer — catches drags on empty space
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(minHeight: geometry.size.height)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("gridContent"))
                                .onChanged { value in
                                    if rubberBandStart == nil {
                                        rubberBandStart = value.startLocation
                                        let flags = NSEvent.modifierFlags
                                        frozenSelection = (flags.contains(.shift) || flags.contains(.command))
                                            ? selectedIds : Set()
                                    }
                                    rubberBandCurrent = value.location

                                    let dx = value.location.x - value.startLocation.x
                                    let dy = value.location.y - value.startLocation.y
                                    if !rubberBandActive && (dx * dx + dy * dy >= 9) {
                                        rubberBandActive = true
                                    }

                                    if rubberBandActive, let rect = rubberBandRect {
                                        var newSelection = frozenSelection
                                        for (id, frame) in itemFrames {
                                            if rect.intersects(frame) {
                                                newSelection.insert(id)
                                            }
                                        }
                                        onSetSelection(newSelection)
                                    }
                                }
                                .onEnded { _ in
                                    if !rubberBandActive && frozenSelection.isEmpty {
                                        // Click on empty space without modifiers — clear selection
                                        onSetSelection([])
                                    }
                                    rubberBandStart = nil
                                    rubberBandCurrent = nil
                                    rubberBandActive = false
                                    frozenSelection = []
                                }
                        )

                    // Content columns
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            LazyVStack(spacing: spacing) {
                                ForEach(itemsForColumn(column, totalColumns: columns)) { item in
                                    let effectiveIds = selectedIds.contains(item.id) && selectedIds.count > 1
                                        ? selectedIds
                                        : Set([item.id])

                                    GridItemView(
                                        item: item,
                                        width: columnWidth,
                                        isSelected: selectedIds.contains(item.id),
                                        spaces: spaces,
                                        activeSpaceId: activeSpaceId,
                                        selectedCount: selectedIds.contains(item.id) ? selectedIds.count : 1,
                                        onSelect: { onSelect(item.id) },
                                        onToggleSelect: { onToggleSelect(item.id) },
                                        onShiftSelect: { onShiftSelect(item.id) },
                                        onDelete: { onDelete(effectiveIds) },
                                        onAssignToSpace: { spaceId in onAssignToSpace(effectiveIds, spaceId) },
                                        onRetryAnalysis: { onRetryAnalysis(item) }
                                    )
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ItemFramePreferenceKey.self,
                                                value: [item.id: geo.frame(in: .named("gridContent"))]
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)  // ImageGrid.tsx:598 — px-4
                    .padding(.top, 20)         // ImageGrid.tsx:598 — pt-5
                    .padding(.bottom, 16)      // ImageGrid.tsx:598 — pb-4

                    // Rubber band visual — ImageGrid.tsx:715: border-blue-400 bg-blue-400/10
                    if let rect = rubberBandRect {
                        Rectangle()
                            .fill(Color.blue.opacity(0.10))
                            .overlay(
                                Rectangle()
                                    .stroke(Color.blue.opacity(0.6), lineWidth: 1)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "gridContent")
                .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                    itemFrames = frames
                }
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
            columnHeights[shortest] += estimatedHeight + 16
        }

        return columnItems[column]
    }
}
