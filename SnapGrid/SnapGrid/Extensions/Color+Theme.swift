import SwiftUI
import AppKit

extension Color {
    // Adaptive colors — respond to light/dark appearance and Increase Contrast automatically.
    // Increase Contrast variants boost text/border contrast for accessibility compliance.

    private static let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

    static let snapBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return highContrast
                ? NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)        // #000000
                : NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)  // #141414
        } else {
            return highContrast
                ? NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)        // #FFFFFF
                : NSColor(red: 0.941, green: 0.961, blue: 0.984, alpha: 1.0)  // #f0f5fb
        }
    })

    static let snapForeground = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)    // #FAFAFA
        } else {
            return NSColor(red: 0.008, green: 0.031, blue: 0.09, alpha: 1.0)  // #020817
        }
    })

    static let snapCard = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return highContrast
                ? NSColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1.0)  // #191919
                : NSColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1.0)  // #1F1F1F
        } else {
            return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)       // #FFFFFF
        }
    })

    static let snapMuted = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return highContrast
                ? NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)        // #333333
                : NSColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D
        } else {
            return highContrast
                ? NSColor(red: 0.918, green: 0.929, blue: 0.945, alpha: 1.0)  // #eaedF1
                : NSColor(red: 0.945, green: 0.961, blue: 0.976, alpha: 1.0)  // #f1f5f9
        }
    })

    static let snapMutedForeground = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return highContrast
                ? NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)     // #C7C7C7
                : NSColor(red: 0.651, green: 0.651, blue: 0.651, alpha: 1.0)  // #A6A6A6
        } else {
            return highContrast
                ? NSColor(red: 0.29, green: 0.33, blue: 0.40, alpha: 1.0)     // #4A5466
                : NSColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1.0)  // #64748b
        }
    })

    static let snapBorder = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return highContrast
                ? NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)     // #404040
                : NSColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1.0)  // #1F1F1F
        } else {
            return highContrast
                ? NSColor(red: 0.78, green: 0.80, blue: 0.83, alpha: 1.0)     // #C7CCD4
                : NSColor(red: 0.886, green: 0.910, blue: 0.941, alpha: 1.0)  // #e2e8f0
        }
    })

    static let snapAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1.0)  // #808080
            : NSColor(red: 0.0, green: 0.502, blue: 1.0, alpha: 1.0)     // #0080FF
    })
}
