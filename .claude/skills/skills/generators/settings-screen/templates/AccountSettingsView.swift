import SwiftUI

/// Account settings view for signed-in users.
///
/// Usage:
/// ```swift
/// NavigationLink("Account") {
///     AccountSettingsView()
/// }
/// ```
struct AccountSettingsView: View {

    // TODO: Replace with your authentication manager
    // @Environment(AuthenticationManager.self) private var authManager

    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        Form {
            // Account Info Section
            accountInfoSection

            // Actions Section
            actionsSection

            // Danger Zone
            dangerZoneSection
        }
        .navigationTitle("Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
    }

    // MARK: - Sections

    private var accountInfoSection: some View {
        Section {
            // TODO: Replace with actual user data
            HStack {
                // User avatar
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("User Name")
                        .font(.headline)
                    Text("user@example.com")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)

            // Member since
            HStack {
                Text("Member Since")
                Spacer()
                Text("January 2024")
                    .foregroundStyle(.secondary)
            }

            // Subscription status (if applicable)
            HStack {
                Text("Subscription")
                Spacer()
                Text("Pro")
                    .foregroundStyle(.green)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            // Edit profile
            NavigationLink {
                EditProfileView()
            } label: {
                Label("Edit Profile", systemImage: "pencil")
            }

            // Change password (if using email auth)
            NavigationLink {
                ChangePasswordView()
            } label: {
                Label("Change Password", systemImage: "key.fill")
            }

            // Manage subscription
            NavigationLink {
                ManageSubscriptionView()
            } label: {
                Label("Manage Subscription", systemImage: "creditcard.fill")
            }
        }
    }

    private var dangerZoneSection: some View {
        Section {
            // Sign out
            Button(role: .destructive) {
                showSignOutConfirmation = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }

            // Delete account
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Label("Delete Account", systemImage: "trash.fill")
                }
            }
            .disabled(isDeleting)
        } footer: {
            Text("Deleting your account will permanently remove all your data.")
        }
    }

    // MARK: - Actions

    private func signOut() {
        // TODO: Implement sign out
        // authManager.signOut()
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        // TODO: Implement account deletion
        // try await authManager.deleteAccount()
    }
}

// MARK: - Placeholder Views

/// Edit profile view placeholder.
private struct EditProfileView: View {
    var body: some View {
        Text("Edit Profile")
            .navigationTitle("Edit Profile")
    }
}

/// Change password view placeholder.
private struct ChangePasswordView: View {
    var body: some View {
        Text("Change Password")
            .navigationTitle("Change Password")
    }
}

/// Manage subscription view placeholder.
private struct ManageSubscriptionView: View {
    var body: some View {
        Text("Manage Subscription")
            .navigationTitle("Subscription")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountSettingsView()
    }
}
