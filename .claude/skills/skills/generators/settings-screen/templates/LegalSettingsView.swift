import SwiftUI

/// Legal settings view with privacy policy, terms, and related links.
///
/// Usage:
/// ```swift
/// NavigationLink("Legal") {
///     LegalSettingsView()
/// }
/// ```
struct LegalSettingsView: View {

    var body: some View {
        Form {
            // Legal documents
            documentsSection

            // Data management
            dataManagementSection
        }
        .navigationTitle("Legal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    private var documentsSection: some View {
        Section {
            // Privacy Policy
            Link(destination: privacyURL) {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Terms of Service
            Link(destination: termsURL) {
                HStack {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // EULA (if applicable for App Store apps)
            Link(destination: eulaURL) {
                HStack {
                    Label("End User License Agreement", systemImage: "doc.plaintext.fill")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } footer: {
            Text("By using this app, you agree to our Privacy Policy and Terms of Service.")
        }
    }

    private var dataManagementSection: some View {
        Section("Your Data") {
            // Data export (GDPR compliance)
            NavigationLink {
                DataExportView()
            } label: {
                Label("Export Your Data", systemImage: "square.and.arrow.up.on.square")
            }

            // Data deletion request
            NavigationLink {
                DataDeletionView()
            } label: {
                Label("Request Data Deletion", systemImage: "trash")
            }
        } footer: {
            Text("You can request a copy of your data or ask us to delete it at any time.")
        }
    }

    // MARK: - URLs

    // TODO: Update these URLs for your app
    private var privacyURL: URL {
        URL(string: "https://yourapp.com/privacy")!
    }

    private var termsURL: URL {
        URL(string: "https://yourapp.com/terms")!
    }

    private var eulaURL: URL {
        URL(string: "https://yourapp.com/eula")!
    }
}

// MARK: - Data Export View

/// View for exporting user data (GDPR compliance).
struct DataExportView: View {

    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Export a copy of all your data in a portable format.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        await exportData()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                            Text("Preparing Export...")
                        } else {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                    }
                }
                .disabled(isExporting)
            } footer: {
                Text("Your data will be exported as a JSON file.")
            }

            if exportComplete {
                Section {
                    Label("Export Complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Export Data")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func exportData() async {
        isExporting = true
        error = nil
        defer { isExporting = false }

        // Simulate export delay
        try? await Task.sleep(for: .seconds(2))

        // TODO: Implement actual data export
        // 1. Gather all user data
        // 2. Convert to JSON
        // 3. Present share sheet

        exportComplete = true
    }
}

// MARK: - Data Deletion View

/// View for requesting data deletion (GDPR compliance).
struct DataDeletionView: View {

    @State private var showConfirmation = false
    @State private var isDeleting = false
    @State private var requestSubmitted = false

    var body: some View {
        Form {
            Section {
                Text("Request permanent deletion of all your data from our servers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What will be deleted:", systemImage: "list.bullet")
                        .font(.headline)

                    Group {
                        Text("• Your account and profile")
                        Text("• All saved content")
                        Text("• Usage history")
                        Text("• Preferences and settings")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button(role: .destructive) {
                    showConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                            Text("Submitting Request...")
                        } else {
                            Label("Request Data Deletion", systemImage: "trash")
                        }
                        Spacer()
                    }
                }
                .disabled(isDeleting || requestSubmitted)
            } footer: {
                Text("This action cannot be undone. Your data will be permanently deleted within 30 days.")
            }

            if requestSubmitted {
                Section {
                    Label("Request Submitted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("We will process your request within 30 days and send you a confirmation email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Delete Data")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Delete All Data", isPresented: $showConfirmation) {
            Button("Delete All Data", role: .destructive) {
                Task {
                    await requestDeletion()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your data. This action cannot be undone.")
        }
    }

    private func requestDeletion() async {
        isDeleting = true
        defer { isDeleting = false }

        // Simulate API call
        try? await Task.sleep(for: .seconds(2))

        // TODO: Implement actual deletion request
        // 1. Send request to backend
        // 2. Sign out user
        // 3. Clear local data

        requestSubmitted = true
    }
}

// MARK: - Preview

#Preview("Legal") {
    NavigationStack {
        LegalSettingsView()
    }
}

#Preview("Export Data") {
    NavigationStack {
        DataExportView()
    }
}

#Preview("Delete Data") {
    NavigationStack {
        DataDeletionView()
    }
}
