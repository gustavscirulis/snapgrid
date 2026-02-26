import SwiftUI

extension Color {
    // Dark theme (primary)
    static let snapBackground = Color(nsColor: NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)) // #141414
    static let snapForeground = Color(nsColor: NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0))    // #FAFAFA
    static let snapCard = Color(nsColor: NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0))       // #1E1E1E
    static let snapMuted = Color(nsColor: NSColor(red: 0.173, green: 0.173, blue: 0.173, alpha: 1.0))      // #2C2C2C
    static let snapBorder = Color(nsColor: NSColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1.0))     // #1F1F1F

    // Light theme
    static let snapLightBackground = Color(nsColor: NSColor(red: 0.98, green: 0.976, blue: 0.969, alpha: 1.0))  // #FAF9F7
    static let snapLightForeground = Color(nsColor: NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)) // #1A1A1A
    static let snapLightCard = Color.white
    static let snapLightMuted = Color(nsColor: NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1.0))      // #F5F5F5
    static let snapLightBorder = Color(nsColor: NSColor(red: 0.902, green: 0.902, blue: 0.902, alpha: 1.0))     // #E6E6E6

    // Accent
    static let snapAccent = Color(nsColor: NSColor(red: 0.0, green: 0.4, blue: 1.0, alpha: 1.0))  // #0066FF
}
