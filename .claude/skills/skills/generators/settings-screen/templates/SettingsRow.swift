import SwiftUI

/// Reusable settings row with icon.
///
/// Usage:
/// ```swift
/// SettingsRow(icon: "bell.fill", iconColor: .red, title: "Notifications") {
///     Text("On")
/// }
/// ```
struct SettingsRow<Content: View>: View {

    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let content: () -> Content

    init(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon with colored background
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

// MARK: - Convenience Initializers

extension SettingsRow where Content == EmptyView {

    /// Create a settings row without trailing content.
    init(icon: String, iconColor: Color, title: String) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = { EmptyView() }
    }
}

extension SettingsRow where Content == Text {

    /// Create a settings row with text value.
    init(icon: String, iconColor: Color, title: String, value: String) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = { Text(value) }
    }
}

// MARK: - Settings Link Row

/// Navigation link styled as a settings row.
struct SettingsLinkRow<Destination: View>: View {

    let icon: String
    let iconColor: Color
    let title: String
    let value: String?
    let destination: () -> Destination

    init(
        icon: String,
        iconColor: Color,
        title: String,
        value: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.value = value
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRow(icon: icon, iconColor: iconColor, title: title) {
                if let value {
                    Text(value)
                }
            }
        }
    }
}

// MARK: - Settings Toggle Row

/// Toggle styled as a settings row.
struct SettingsToggleRow: View {

    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 6))

                Text(title)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Form {
            Section("Examples") {
                SettingsRow(icon: "gear", iconColor: .gray, title: "General") {
                    Text("Value")
                }

                SettingsRow(icon: "bell.fill", iconColor: .red, title: "Notifications", value: "On")

                SettingsLinkRow(
                    icon: "paintbrush.fill",
                    iconColor: .purple,
                    title: "Appearance",
                    value: "System"
                ) {
                    Text("Appearance Settings")
                }

                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    iconColor: .blue,
                    title: "Haptic Feedback",
                    isOn: .constant(true)
                )
            }
        }
        .navigationTitle("Settings")
    }
}
