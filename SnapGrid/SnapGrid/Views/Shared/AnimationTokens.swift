import SwiftUI

/// Named animation presets for consistent motion across the app.
///
/// Three tiers:
///  - **fast**     — micro-interactions: hover shadows, button reveals, small state toggles
///  - **standard** — UI transitions: tab switches, toasts, selection badges, carousel slides
///  - **hero**     — page-level: detail overlay expand/collapse
enum SnapSpring {
    static let fast     = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let hero     = Animation.spring(response: 0.36, dampingFraction: 0.87)
}
