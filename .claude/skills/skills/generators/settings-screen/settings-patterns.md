# Settings Screen Patterns

Best practices for implementing settings screens in iOS and macOS apps.

## Architecture Patterns

### Centralized Settings with @AppStorage

Use a single `AppSettings` class to manage all user preferences:

```swift
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // Appearance
    @AppStorage("appearance") var appearance: Appearance = .system
    @AppStorage("accentColor") var accentColor: AccentColor = .blue

    // Behavior
    @AppStorage("hapticFeedback") var hapticFeedback = true
    @AppStorage("soundEffects") var soundEffects = true

    // Privacy
    @AppStorage("analyticsEnabled") var analyticsEnabled = true

    private init() {}
}
```

**Benefits:**
- Single source of truth
- Type-safe access
- Automatic persistence
- Easy to mock for testing

### Environment Integration

Inject settings into SwiftUI environment:

```swift
// In App.swift
@main
struct MyApp: App {
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
    }
}

// In any view
struct FeatureView: View {
    @Environment(AppSettings.self) var settings

    var body: some View {
        if settings.hapticFeedback {
            // Use haptics
        }
    }
}
```

## UI Patterns

### Grouped List with Form

Standard iOS settings appearance:

```swift
var body: some View {
    Form {
        Section("Appearance") {
            // Appearance settings
        }

        Section("Notifications") {
            // Notification settings
        }

        Section("About") {
            // About info
        }
    }
    .navigationTitle("Settings")
}
```

### Settings Row with Icon

Consistent row styling:

```swift
struct SettingsRow<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 6))

            Text(title)

            Spacer()

            content()
                .foregroundStyle(.secondary)
        }
    }
}

// Usage
SettingsRow(icon: "bell.fill", iconColor: .red, title: "Notifications") {
    Text(notificationsEnabled ? "On" : "Off")
}
```

### Navigation Links

For sub-screens:

```swift
NavigationLink {
    AppearanceSettingsView()
} label: {
    SettingsRow(icon: "paintbrush.fill", iconColor: .purple, title: "Appearance") {
        Text(settings.appearance.displayName)
    }
}
```

### Toggle Rows

For boolean settings:

```swift
Toggle(isOn: $settings.hapticFeedback) {
    Label("Haptic Feedback", systemImage: "hand.tap.fill")
}
```

### Picker Rows

For selection settings:

```swift
Picker("Appearance", selection: $settings.appearance) {
    ForEach(Appearance.allCases, id: \.self) { appearance in
        Text(appearance.displayName).tag(appearance)
    }
}
```

## Platform-Specific Patterns

### iOS Settings Link

Open device Settings app:

```swift
Button("Open Settings") {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
```

### macOS Settings Scene

Standard preferences window:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            SettingsView()
        }
    }
}
```

With tabs for multiple sections:

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 450, height: 300)
    }
}
```

### Cross-Platform Adaptive

```swift
struct SettingsView: View {
    var body: some View {
        #if os(iOS)
        NavigationStack {
            settingsContent
                .navigationTitle("Settings")
        }
        #else
        TabView {
            settingsContent
        }
        .frame(width: 450, height: 300)
        #endif
    }

    private var settingsContent: some View {
        Form {
            // Settings sections
        }
    }
}
```

## Common Settings Sections

### Appearance Section

```swift
Section("Appearance") {
    Picker("Theme", selection: $settings.appearance) {
        Text("System").tag(Appearance.system)
        Text("Light").tag(Appearance.light)
        Text("Dark").tag(Appearance.dark)
    }

    if supportsAlternateIcons {
        NavigationLink("App Icon") {
            AppIconPickerView()
        }
    }
}
```

### Notifications Section

```swift
Section("Notifications") {
    Toggle("Push Notifications", isOn: $settings.notificationsEnabled)
        .onChange(of: settings.notificationsEnabled) { _, newValue in
            if newValue {
                requestNotificationPermission()
            }
        }

    if settings.notificationsEnabled {
        Toggle("Daily Reminders", isOn: $settings.dailyReminders)
        Toggle("Weekly Summary", isOn: $settings.weeklySummary)
    }
}
```

### About Section

```swift
Section("About") {
    HStack {
        Text("Version")
        Spacer()
        Text(appVersion)
            .foregroundStyle(.secondary)
    }

    Link("Rate on App Store", destination: appStoreURL)

    Link("Contact Support", destination: supportURL)

    NavigationLink("Acknowledgements") {
        AcknowledgementsView()
    }
}
```

### Legal Section

```swift
Section("Legal") {
    Link("Privacy Policy", destination: privacyURL)
    Link("Terms of Service", destination: termsURL)
    NavigationLink("Licenses") {
        LicensesView()
    }
}
```

### Account Section

```swift
Section("Account") {
    if let user = authManager.currentUser {
        HStack {
            Text("Signed in as")
            Spacer()
            Text(user.email)
                .foregroundStyle(.secondary)
        }

        Button("Sign Out", role: .destructive) {
            showSignOutConfirmation = true
        }
    } else {
        Button("Sign In") {
            showSignIn = true
        }
    }
}

Section {
    Button("Delete Account", role: .destructive) {
        showDeleteConfirmation = true
    }
}
```

### Data & Privacy Section

```swift
Section("Data & Privacy") {
    Toggle("Analytics", isOn: $settings.analyticsEnabled)

    Button("Export Data") {
        exportUserData()
    }

    Button("Clear Cache") {
        clearCache()
    }

    HStack {
        Text("Storage Used")
        Spacer()
        Text(formattedStorageSize)
            .foregroundStyle(.secondary)
    }
}
```

## App Icon Picker

For apps with alternate icons:

```swift
struct AppIconPickerView: View {
    @State private var selectedIcon: String? = nil

    let icons = ["AppIcon", "AppIcon-Dark", "AppIcon-Pride"]

    var body: some View {
        List(icons, id: \.self) { iconName in
            Button {
                setAppIcon(iconName)
            } label: {
                HStack {
                    Image(iconName + "-Preview")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .cornerRadius(12)

                    Text(iconDisplayName(iconName))

                    Spacer()

                    if selectedIcon == iconName {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("App Icon")
        .onAppear {
            selectedIcon = UIApplication.shared.alternateIconName ?? "AppIcon"
        }
    }

    private func setAppIcon(_ name: String) {
        let iconName = name == "AppIcon" ? nil : name
        UIApplication.shared.setAlternateIconName(iconName)
        selectedIcon = name
    }
}
```

## Confirmation Dialogs

For destructive actions:

```swift
.confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation) {
    Button("Sign Out", role: .destructive) {
        authManager.signOut()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Are you sure you want to sign out?")
}

.confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation) {
    Button("Delete Account", role: .destructive) {
        deleteAccount()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This action cannot be undone. All your data will be permanently deleted.")
}
```

## Version and Build Info

```swift
var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    return "\(version) (\(build))"
}
```

## Debug Settings (Development Only)

```swift
#if DEBUG
Section("Debug") {
    Button("Reset Onboarding") {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }

    Button("Clear All Data") {
        clearAllData()
    }

    Toggle("Show Debug Info", isOn: $settings.showDebugInfo)

    NavigationLink("Feature Flags") {
        FeatureFlagsView()
    }
}
#endif
```

## Accessibility

Ensure settings are accessible:

```swift
Toggle("Reduce Motion", isOn: $settings.reduceMotion)
    .accessibilityHint("Reduces animations throughout the app")

Button("Clear Cache") {
    clearCache()
}
.accessibilityLabel("Clear cached data")
.accessibilityHint("Frees up storage space by removing cached files")
```

## Testing Settings

Mock AppSettings for testing:

```swift
final class MockAppSettings: AppSettings {
    override init() {
        super.init()
        // Set test defaults
        appearance = .light
        notificationsEnabled = false
    }
}

// In previews
#Preview {
    SettingsView()
        .environment(MockAppSettings())
}
```
