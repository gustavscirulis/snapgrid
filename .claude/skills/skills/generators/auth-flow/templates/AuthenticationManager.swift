import Foundation
import AuthenticationServices

/// Central authentication manager.
///
/// Coordinates Sign in with Apple, biometrics, and session management.
///
/// Usage:
/// ```swift
/// @main
/// struct MyApp: App {
///     @State private var authManager = AuthenticationManager()
///
///     var body: some Scene {
///         WindowGroup {
///             if authManager.isAuthenticated {
///                 ContentView()
///             } else {
///                 AuthenticationView()
///             }
///         }
///         .environment(authManager)
///     }
/// }
/// ```
@MainActor
@Observable
final class AuthenticationManager {

    // MARK: - Published State

    /// Whether user is currently authenticated.
    private(set) var isAuthenticated = false

    /// Current user info (if authenticated).
    private(set) var currentUser: AuthenticatedUser?

    /// Any authentication error.
    private(set) var error: AuthenticationError?

    /// Whether authentication is in progress.
    private(set) var isLoading = false

    // MARK: - Initialization

    init() {
        // Check for existing session on init
        Task {
            await checkExistingSession()
        }
    }

    // MARK: - Sign in with Apple

    /// Handle Sign in with Apple result.
    func handleSignInWithApple(_ result: Result<ASAuthorization, Error>) {
        isLoading = true
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = .invalidCredential
                return
            }

            // Extract user info
            let userID = credential.user

            // Name only on first sign-in - save immediately
            var name: String?
            if let fullName = credential.fullName {
                name = PersonNameComponentsFormatter().string(from: fullName)
            }

            // Email may be real or relay
            let email = credential.email

            // Save to Keychain
            saveCredentials(userID: userID, name: name, email: email)

            // Update state
            currentUser = AuthenticatedUser(
                id: userID,
                name: name ?? KeychainManager.shared.get(.userName),
                email: email ?? KeychainManager.shared.get(.userEmail)
            )
            isAuthenticated = true
            error = nil

        case .failure(let authError):
            if let asError = authError as? ASAuthorizationError {
                switch asError.code {
                case .canceled:
                    // User cancelled - not an error
                    break
                case .failed:
                    error = .failed(authError)
                case .invalidResponse:
                    error = .invalidCredential
                case .notHandled:
                    error = .failed(authError)
                case .unknown:
                    error = .unknown
                case .notInteractive:
                    error = .failed(authError)
                @unknown default:
                    error = .unknown
                }
            } else {
                error = .failed(authError)
            }
        }
    }

    // MARK: - Biometric Authentication

    /// Authenticate using Face ID or Touch ID.
    func authenticateWithBiometrics() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        let success = await BiometricAuthManager.shared.authenticate()

        if success {
            // Load saved user
            if let userID = KeychainManager.shared.get(.userID) {
                currentUser = AuthenticatedUser(
                    id: userID,
                    name: KeychainManager.shared.get(.userName),
                    email: KeychainManager.shared.get(.userEmail)
                )
                isAuthenticated = true
            }
        }

        return success
    }

    // MARK: - Sign Out

    /// Sign out and clear all credentials.
    func signOut() {
        KeychainManager.shared.clearAll()
        currentUser = nil
        isAuthenticated = false
        error = nil
    }

    // MARK: - Credential State

    /// Check if existing credentials are still valid.
    func checkCredentialState() async {
        guard let userID = KeychainManager.shared.get(.userID) else {
            isAuthenticated = false
            return
        }

        let state = await SignInWithAppleManager.shared.checkCredentialState(userID: userID)

        switch state {
        case .authorized:
            // Still valid
            currentUser = AuthenticatedUser(
                id: userID,
                name: KeychainManager.shared.get(.userName),
                email: KeychainManager.shared.get(.userEmail)
            )
            isAuthenticated = true

        case .revoked, .notFound:
            // User revoked or doesn't exist
            signOut()

        case .transferred:
            // Handle account transfer if needed
            signOut()

        @unknown default:
            break
        }
    }

    // MARK: - Private

    private func checkExistingSession() async {
        guard KeychainManager.shared.get(.userID) != nil else {
            return
        }
        await checkCredentialState()
    }

    private func saveCredentials(userID: String, name: String?, email: String?) {
        KeychainManager.shared.save(userID, for: .userID)

        if let name = name {
            KeychainManager.shared.save(name, for: .userName)
        }

        if let email = email {
            KeychainManager.shared.save(email, for: .userEmail)
        }
    }
}

// MARK: - Models

/// Authenticated user information.
struct AuthenticatedUser: Sendable {
    let id: String
    let name: String?
    let email: String?
}

/// Authentication errors.
enum AuthenticationError: Error, LocalizedError {
    case invalidCredential
    case failed(Error)
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid credentials received"
        case .failed(let error):
            return error.localizedDescription
        case .cancelled:
            return "Authentication was cancelled"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
