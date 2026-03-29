import SwiftUI
import UIKit

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
    static let metadata = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Brief ease-out used when Reduce Motion is enabled.
    private static let reduced = Animation.easeOut(duration: 0.2)

    /// Returns a brief ease-out when Reduce Motion is on, otherwise the given spring.
    static func resolved(_ spring: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled ? reduced : spring
    }

    static var resolvedFast: Animation     { resolved(fast) }
    static var resolvedStandard: Animation { resolved(standard) }
    static var resolvedHero: Animation     { resolved(hero) }
    static var resolvedMetadata: Animation { resolved(metadata) }
}
