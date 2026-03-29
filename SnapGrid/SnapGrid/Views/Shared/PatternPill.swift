import SwiftUI

/// Hover-state pattern name pill used on grid thumbnails and the floating video layer.
/// Uses `.ultraThinMaterial` so it composites correctly above NSView-backed video content.
struct PatternPill: View {
    let name: String
    var large: Bool = false

    var body: some View {
        Text(name)
            .font(large ? .subheadline : .callout)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, large ? 10 : 8)
            .padding(.vertical, large ? 5 : 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: large ? 12 : 10))
            .environment(\.colorScheme, .dark)
    }
}
