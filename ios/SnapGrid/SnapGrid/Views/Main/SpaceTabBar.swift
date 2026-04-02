import SwiftUI

struct SpaceTabBar: View {
    let spaces: [Space]
    @Binding var activeSpaceId: String?
    var scrollProgress: CGFloat
    var onAssignToSpace: ((String, String?) -> Void)?

    @State private var dropTargetId: String?

    private var activeIndex: Int {
        guard let id = activeSpaceId else { return 0 }
        return (spaces.firstIndex { $0.id == id } ?? -1) + 1
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                tabDropTarget(title: "All", index: 0, spaceId: nil, isActive: activeSpaceId == nil)

                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    tabDropTarget(title: space.name, index: index + 1, spaceId: space.id, isActive: activeSpaceId == space.id)
                }
            }
            .padding(.horizontal, 12)
            .overlayPreferenceValue(TabAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    let frames = anchors.mapValues { proxy[$0] }
                    tabUnderline(frames: frames, containerHeight: proxy.size.height)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Tab with Drop Target

    @ViewBuilder
    private func tabDropTarget(title: String, index: Int, spaceId: String?, isActive: Bool) -> some View {
        let targetId = spaceId ?? "ALL"
        let isDropTarget = dropTargetId == targetId

        TabButton(title: title, index: index, isActive: isActive, isDropTarget: isDropTarget) {
            withAnimation(SnapSpring.resolvedStandard) {
                activeSpaceId = spaceId
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { strings, _ in
            handleDrop(strings, spaceId: spaceId)
        } isTargeted: { targeted in
            withAnimation(SnapSpring.resolvedFast) {
                dropTargetId = targeted ? targetId : nil
            }
            if targeted {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ strings: [String], spaceId: String?) -> Bool {
        for text in strings {
            if text.hasPrefix("snapgrid:") {
                let itemId = String(text.dropFirst("snapgrid:".count))
                if !itemId.isEmpty {
                    onAssignToSpace?(itemId, spaceId)
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Tab Underline

    @ViewBuilder
    private func tabUnderline(frames: [Int: CGRect], containerHeight: CGFloat) -> some View {
        let inset: CGFloat = 8
        let floorIndex = max(0, Int(scrollProgress))
        let ceilIndex = floorIndex + 1
        let fraction = scrollProgress - CGFloat(floorIndex)

        if let fromFrame = frames[floorIndex] {
            let toFrame = frames[ceilIndex] ?? fromFrame

            let currentWidth = lerp(from: fromFrame.width - inset * 2, to: toFrame.width - inset * 2, t: fraction)
            let currentX = lerp(from: fromFrame.midX, to: toFrame.midX, t: fraction)

            Capsule()
                .fill(Color.white)
                .frame(width: max(0, currentWidth), height: 2)
                .position(x: currentX, y: containerHeight - 1)
        }
    }

    private func lerp(from: CGFloat, to: CGFloat, t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }
}

// MARK: - Preference Key for tab frame anchors

private struct TabAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let index: Int
    let isActive: Bool
    var isDropTarget: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .hidden()
                .overlay {
                    Text(title)
                        .font(.subheadline.weight(isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? .white : isDropTarget ? .white.opacity(0.7) : .white.opacity(0.5))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(minWidth: 44)
                .background {
                    if isDropTarget && !isActive {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .anchorPreference(key: TabAnchorPreferenceKey.self, value: .bounds) { anchor in
            [index: anchor]
        }
    }
}
