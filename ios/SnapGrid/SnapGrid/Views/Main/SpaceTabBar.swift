import SwiftUI

struct SpaceTabBar: View {
    let spaces: [Space]
    @Binding var activeSpaceId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TabButton(
                    title: "All",
                    isActive: activeSpaceId == nil
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeSpaceId = nil
                    }
                }

                ForEach(spaces) { space in
                    TabButton(
                        title: space.name,
                        isActive: activeSpaceId == space.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeSpaceId = space.id
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isActive
                        ? Color.white.opacity(0.12)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
