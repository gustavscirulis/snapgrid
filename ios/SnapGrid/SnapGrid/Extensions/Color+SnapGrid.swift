import SwiftUI

extension Color {
    // Light mode
    static let snapBackground = Color(red: 0.98, green: 0.976, blue: 0.969)       // #FAF9F7
    static let snapForeground = Color(red: 0.102, green: 0.102, blue: 0.102)      // #1A1A1A
    static let snapCard = Color.white                                               // #FFFFFF
    static let snapMuted = Color(red: 0.961, green: 0.961, blue: 0.961)           // #F5F5F5
    static let snapBorder = Color(red: 0.902, green: 0.902, blue: 0.902)          // #E6E6E6

    // Dark mode
    static let snapDarkBackground = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let snapDarkForeground = Color(red: 0.98, green: 0.98, blue: 0.98)     // #FAFAFA
    static let snapDarkCard = Color(red: 0.118, green: 0.118, blue: 0.118)        // #1E1E1E
    static let snapDarkMuted = Color(red: 0.173, green: 0.173, blue: 0.173)       // #2C2C2C
    static let snapDarkBorder = Color(red: 0.122, green: 0.122, blue: 0.122)      // #1F1F1F
}

extension ShapeStyle where Self == Color {
    static var snapAdaptiveBackground: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color.snapDarkBackground)
                : UIColor(Color.snapBackground)
        })
    }

    static var snapAdaptiveCard: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color.snapDarkCard)
                : UIColor(Color.snapCard)
        })
    }

    static var snapAdaptiveMuted: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color.snapDarkMuted)
                : UIColor(Color.snapMuted)
        })
    }
}
