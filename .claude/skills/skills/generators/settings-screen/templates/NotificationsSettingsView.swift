import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Dedicated notifications settings view.
///
/// Usage:
/// ```swift
/// NavigationLink("Notifications") {
///     NotificationsSettingsView()
/// }
/// ```
struct NotificationsSettingsView: View {

    @State private var settings = AppSettings.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingPermission = false

    var body: some View {
        Form {
            // Permission status
            permissionSection

            // Notification types (only show if authorized)
            if notificationStatus == .authorized {
                notificationTypesSection
            }

            // System settings link
            #if os(iOS)
            systemSettingsSection
            #endif
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await checkNotificationStatus()
        }
    }

    // MARK: - Sections

    private var permissionSection: some View {
        Section {
            HStack {
                Label {
                    Text("Push Notifications")
                } icon: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(statusColor)
                }

                Spacer()

                statusBadge
            }

            if notificationStatus == .notDetermined {
                Button {
                    Task {
                        await requestPermission()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isRequestingPermission {
                            ProgressView()
                        } else {
                            Text("Enable Notifications")
                        }
                        Spacer()
                    }
                }
                .disabled(isRequestingPermission)
            }
        } footer: {
            Text(statusFooterText)
        }
    }

    private var notificationTypesSection: some View {
        Section("Notification Types") {
            Toggle("Daily Reminders", isOn: $settings.dailyReminders)

            if settings.dailyReminders {
                // TODO: Add time picker for reminder time
                HStack {
                    Text("Reminder Time")
                    Spacer()
                    Text("9:00 AM")
                        .foregroundStyle(.secondary)
                }
            }

            // Add more notification type toggles as needed
            // Toggle("Weekly Summary", isOn: $settings.weeklySummary)
            // Toggle("New Content", isOn: $settings.newContentNotifications)
        }
    }

    #if os(iOS)
    private var systemSettingsSection: some View {
        Section {
            Button {
                openSystemSettings()
            } label: {
                HStack {
                    Label("System Notification Settings", systemImage: "gear")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Manage notification badges, sounds, and banners in system settings.")
        }
    }
    #endif

    // MARK: - Status Display

    private var statusColor: Color {
        switch notificationStatus {
        case .authorized: return .green
        case .denied: return .red
        case .provisional: return .yellow
        case .notDetermined: return .gray
        case .ephemeral: return .blue
        @unknown default: return .gray
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch notificationStatus {
        case .authorized:
            Text("Enabled")
                .font(.caption)
                .foregroundStyle(.green)
        case .denied:
            Text("Disabled")
                .font(.caption)
                .foregroundStyle(.red)
        case .provisional:
            Text("Provisional")
                .font(.caption)
                .foregroundStyle(.yellow)
        case .notDetermined:
            Text("Not Set")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var statusFooterText: String {
        switch notificationStatus {
        case .authorized:
            return "You'll receive notifications for enabled types."
        case .denied:
            return "Notifications are disabled. Enable them in system settings to receive updates."
        case .notDetermined:
            return "Enable notifications to stay updated."
        default:
            return ""
        }
    }

    // MARK: - Actions

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
        }
    }

    private func requestPermission() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])

            await MainActor.run {
                notificationStatus = granted ? .authorized : .denied
            }
        } catch {
            print("Failed to request notification permission: \(error)")
        }
    }

    #if os(iOS)
    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    #endif
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationsSettingsView()
    }
}
