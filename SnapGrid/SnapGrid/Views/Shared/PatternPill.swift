import SwiftUI

/// Hover-state pattern name pill used on grid thumbnails and the floating video layer.
/// Uses `.ultraThinMaterial` so it composites correctly above NSView-backed video content.
struct PatternPill: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .dark)
    }
}
