import SwiftUI

/// About settings view with app info, links, and acknowledgements.
///
/// Usage:
/// ```swift
/// NavigationLink("About") {
///     AboutSettingsView()
/// }
/// ```
struct AboutSettingsView: View {

    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            // App info
            appInfoSection

            // Links
            linksSection

            // Credits
            creditsSection
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    private var appInfoSection: some View {
        Section {
            VStack(spacing: 12) {
                // App icon
                Image(systemName: "app.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.accentColor)

                // App name
                Text("Your App Name")
                    .font(.title2.bold())

                // Version
                Text("Version \(settings.fullVersionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var linksSection: some View {
        Section {
            // App Store rating
            Link(destination: appStoreURL) {
                HStack {
                    Label("Rate on App Store", systemImage: "star.fill")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Share app
            ShareLink(item: appStoreURL) {
                Label("Share App", systemImage: "square.and.arrow.up")
            }

            // Contact support
            Link(destination: supportURL) {
                HStack {
                    Label("Contact Support", systemImage: "envelope.fill")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Website
            Link(destination: websiteURL) {
                HStack {
                    Label("Website", systemImage: "globe")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var creditsSection: some View {
        Section("Credits") {
            // Developer info
            HStack {
                Text("Developed by")
                Spacer()
                Text("Your Name")
                    .foregroundStyle(.secondary)
            }

            // Acknowledgements
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("Acknowledgements", systemImage: "heart.fill")
            }

            // Open source licenses
            NavigationLink {
                LicensesView()
            } label: {
                Label("Open Source Licenses", systemImage: "doc.text.fill")
            }
        }
    }

    // MARK: - URLs

    // TODO: Update these URLs for your app
    private var appStoreURL: URL {
        URL(string: "https://apps.apple.com/app/idYOUR_APP_ID")!
    }

    private var supportURL: URL {
        URL(string: "mailto:support@yourapp.com")!
    }

    private var websiteURL: URL {
        URL(string: "https://yourapp.com")!
    }
}

// MARK: - Acknowledgements View

/// View showing acknowledgements and credits.
struct AcknowledgementsView: View {

    var body: some View {
        List {
            Section {
                Text("Thank you to everyone who has supported this app's development.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Special Thanks") {
                acknowledgementRow(
                    name: "Apple",
                    reason: "For Swift and SwiftUI"
                )
                acknowledgementRow(
                    name: "The Swift Community",
                    reason: "For amazing open source libraries"
                )
                // Add more acknowledgements as needed
            }

            Section("Beta Testers") {
                Text("All our amazing beta testers who helped improve the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Acknowledgements")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func acknowledgementRow(name: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Licenses View

/// View showing open source licenses.
struct LicensesView: View {

    var body: some View {
        List {
            Section {
                Text("This app uses the following open source libraries:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Add your open source dependencies here
            Section {
                licenseRow(
                    name: "Example Library",
                    license: "MIT License",
                    url: "https://github.com/example/library"
                )
                // Add more licenses as needed
            }
        }
        .navigationTitle("Licenses")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func licenseRow(name: String, license: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(license)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let licenseURL = URL(string: url) {
                Link(url, destination: licenseURL)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("About") {
    NavigationStack {
        AboutSettingsView()
    }
}

#Preview("Acknowledgements") {
    NavigationStack {
        AcknowledgementsView()
    }
}

#Preview("Licenses") {
    NavigationStack {
        LicensesView()
    }
}
