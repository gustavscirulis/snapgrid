import SwiftUI

/// Dedicated appearance settings view.
///
/// Use for apps with more appearance options like app icons.
struct AppearanceSettingsView: View {

    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { appearance in
                        HStack {
                            Image(systemName: iconForAppearance(appearance))
                            Text(appearance.displayName)
                        }
                        .tag(appearance)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Effects") {
                Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                Toggle("Haptic Feedback", isOn: $settings.hapticFeedback)
                Toggle("Sound Effects", isOn: $settings.soundEffects)
            }

            // Uncomment if your app supports alternate icons
            // Section("App Icon") {
            //     AppIconPickerView()
            // }
        }
        .navigationTitle("Appearance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func iconForAppearance(_ appearance: AppSettings.Appearance) -> String {
        switch appearance {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - App Icon Picker

#if os(iOS)
/// Picker for alternate app icons.
///
/// To use:
/// 1. Add alternate icons to your asset catalog
/// 2. Configure in Info.plist under CFBundleIcons
/// 3. Add preview images named "[IconName]-Preview"
struct AppIconPickerView: View {

    @State private var selectedIcon: String?

    /// Available icon names (must match asset catalog and Info.plist)
    let icons = [
        ("AppIcon", "Default"),
        ("AppIcon-Dark", "Dark"),
        ("AppIcon-Light", "Light"),
    ]

    var body: some View {
        ForEach(icons, id: \.0) { iconName, displayName in
            Button {
                setAppIcon(iconName)
            } label: {
                HStack(spacing: 12) {
                    // Icon preview image
                    Image("\(iconName)-Preview")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    Text(displayName)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isSelected(iconName) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.accentColor)
                            .fontWeight(.semibold)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            selectedIcon = currentIconName
        }
    }

    private var currentIconName: String {
        UIApplication.shared.alternateIconName ?? "AppIcon"
    }

    private func isSelected(_ iconName: String) -> Bool {
        if iconName == "AppIcon" {
            return selectedIcon == nil || selectedIcon == "AppIcon"
        }
        return selectedIcon == iconName
    }

    private func setAppIcon(_ name: String) {
        let iconName = name == "AppIcon" ? nil : name

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error {
                print("Failed to set app icon: \(error.localizedDescription)")
            } else {
                selectedIcon = name
            }
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
