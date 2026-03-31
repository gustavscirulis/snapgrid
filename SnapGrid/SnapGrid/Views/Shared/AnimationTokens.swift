import SwiftUI

/// Named animation presets for consistent motion across the app.
///
/// Three tiers:
///  - **fast**     — micro-interactions: hover shadows, button reveals, small state toggles
///  - **standard** — UI transitions: tab switches, toasts, selection badges, carousel slides
///  - **hero**     — page-level: detail overlay expand/collapse
///
/// All presets have reduced-motion variants that use short ease curves instead of springs.
/// Views should read `@Environment(\.accessibilityReduceMotion)` and pass it to
/// the `reduced:` overloads, or use the static lets when reduce-motion is handled elsewhere.
enum SnapSpring {
    static let fast     = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let hero     = Animation.spring(response: 0.36, dampingFraction: 0.87)
    static let metadata = Animation.spring(response: 0.4, dampingFraction: 0.85)

    // MARK: - Reduce Motion Variants

    static func fast(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.1) : fast
    }

    static func standard(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : standard
    }

    static func hero(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.2) : hero
    }

    static func metadata(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : metadata
    }
}

/// Card-crush delete animation presets (matches iOS wallet-style crush).
enum CardCrush {
    static let heightCrush = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let widthCrush  = Animation.spring(response: 0.15, dampingFraction: 0.92)
    static let widthDelay: Duration = .milliseconds(160)
    static let completeDelay: Duration = .milliseconds(300)
    static let crushedScaleY: CGFloat = 0.05
    static let crushedScaleX: CGFloat = 0.0

    static let reducedMotionFade = Animation.easeInOut(duration: 0.15)
    static let reducedMotionDelay: Duration = .milliseconds(200)
}
