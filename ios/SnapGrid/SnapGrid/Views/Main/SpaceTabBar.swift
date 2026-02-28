import SwiftUI

struct SpaceTabBar: View {
    let spaces: [Space]
    @Binding var activeSpaceId: String?
    var scrollProgress: CGFloat

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
        let inset: CGFloat = 12
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
