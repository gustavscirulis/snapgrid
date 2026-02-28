import SwiftUI

struct SpaceTabBar: View {
    let spaces: [Space]
    @Binding var activeSpaceId: String?

    private var activeIndex: Int {
        guard let id = activeSpaceId else { return 0 }
        return (spaces.firstIndex { $0.id == id } ?? -1) + 1
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                TabButton(title: "All", index: 0, isActive: activeSpaceId == nil) {
                    activeSpaceId = nil
                }

                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    TabButton(title: space.name, index: index + 1, isActive: activeSpaceId == space.id) {
                        activeSpaceId = space.id
                    }
                }
            }
            .padding(.horizontal, 12)
            .overlayPreferenceValue(TabAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    let frames = anchors.mapValues { proxy[$0] }
                    tabUnderline(frames: frames, containerHeight: proxy.size.height)
                }
                .animation(.spring(duration: 0.35, bounce: 0.15), value: activeIndex)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func tabUnderline(frames: [Int: CGRect], containerHeight: CGFloat) -> some View {
        if let frame = frames[activeIndex] {
            let inset: CGFloat = 12
            Capsule()
                .fill(Color.white)
                .frame(width: max(0, frame.width - inset * 2), height: 2)
                .position(x: frame.midX, y: containerHeight - 1)
        }
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
    let action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .anchorPreference(key: TabAnchorPreferenceKey.self, value: .bounds) { anchor in
            [index: anchor]
        }
    }
}
