import SwiftUI

/// Hover-state pattern name pill used on grid thumbnails and the floating video layer.
/// Uses `.ultraThinMaterial` so it composites correctly above NSView-backed video content.
struct PatternPill: View {
    let name: String
    var size: CGFloat = 11

    var body: some View {
        Text(name)
            .font(.system(size: size))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, size <= 11 ? 8 : 10)
            .padding(.vertical, size <= 11 ? 3 : 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: size <= 11 ? 10 : 12))
            .environment(\.colorScheme, .dark)
    }
}
