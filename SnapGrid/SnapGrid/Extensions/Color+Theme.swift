import SwiftUI
import AppKit

extension Color {
    // Adaptive colors — respond to light/dark appearance automatically
    // Values from Electron's src/index.css CSS custom properties

    static let snapBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)  // #141414 — index.css:39
            : NSColor(red: 0.941, green: 0.961, blue: 0.984, alpha: 1.0)  // #f0f5fb — index.css:7
    })

    static let snapForeground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)     // #FAFAFA — index.css:40
            : NSColor(red: 0.008, green: 0.031, blue: 0.09, alpha: 1.0)   // #020817 — index.css:8
    })

    static let snapCard = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1.0)  // #1F1F1F — index.css:41
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)       // #FFFFFF — index.css:10
    })

    static let snapMuted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D — index.css:54
            : NSColor(red: 0.945, green: 0.961, blue: 0.976, alpha: 1.0)  // #f1f5f9 — index.css:22
    })

    static let snapMutedForeground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.651, green: 0.651, blue: 0.651, alpha: 1.0)  // #A6A6A6 — index.css:56
            : NSColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1.0)  // #64748b — index.css:24
    })

    static let snapBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1.0)  // #1F1F1F — index.css:63
            : NSColor(red: 0.886, green: 0.910, blue: 0.941, alpha: 1.0)  // #e2e8f0 — index.css:31
    })

    // Accent — adaptive: blue in light, gray in dark (per index.css:16,48)
    static let snapAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1.0)  // #808080 — index.css:48
            : NSColor(red: 0.0, green: 0.502, blue: 1.0, alpha: 1.0)     // #0080FF — index.css:16
    })
}

// MARK: - Theme

enum AppTheme: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
