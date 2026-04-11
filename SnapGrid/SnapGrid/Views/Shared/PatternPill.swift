import SwiftUI

/// Hover-state pattern name pill used on grid thumbnails and the floating video layer.
/// On macOS 26+ uses Liquid Glass; falls back to `.ultraThinMaterial` for compositing
/// above NSView-backed video content on earlier systems.
struct PatternPill: View {
    let name: String
    var large: Bool = false
    /// Set to `false` when rendering above NSViewRepresentable layers where
    /// `.glassEffect()` may not composite correctly (e.g. FloatingVideoLayer).
    var useGlass: Bool = true

    private var cornerRadius: CGFloat { large ? 12 : 10 }

    var body: some View {
        let base = Text(name)
            .font(large ? .subheadline : .callout)
            .foregroundStyle(large ? AnyShapeStyle(.primary) : AnyShapeStyle(.white.opacity(0.9)))
            .padding(.horizontal, large ? 12 : 8)
            .padding(.vertical, large ? 4 : 4)

        #if compiler(>=6.3)
        if #available(macOS 26, *), useGlass {
            if large {
                base.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                base
                    .glassEffect(.regular.tint(.black.opacity(0.3)), in: .rect(cornerRadius: cornerRadius))
                    .environment(\.colorScheme, .dark)
            }
        } else {
            if large {
                base.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                base
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .environment(\.colorScheme, .dark)
            }
        }
        #else
        if large {
            base.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .environment(\.colorScheme, .dark)
        }
        #endif
    }
}
