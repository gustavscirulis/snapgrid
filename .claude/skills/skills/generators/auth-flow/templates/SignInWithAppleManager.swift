import Foundation
import AuthenticationServices

/// Manager for Sign in with Apple.
///
/// Handles credential requests and state checking.
final class SignInWithAppleManager: Sendable {

    // MARK: - Singleton

    static let shared = SignInWithAppleManager()

    private init() {}

    // MARK: - Credential State

    /// Check the current credential state for a user ID.
    func checkCredentialState(userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    // MARK: - Create Request

    /// Create an authorization request for Sign in with Apple.
    func createRequest() -> ASAuthorizationAppleIDRequest {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        return request
    }

    /// Create authorization requests including existing credentials.
    ///
    /// This allows seamless sign-in if user already has Apple ID credentials.
    func createRequests() -> [ASAuthorizationRequest] {
        let appleIDRequest = createRequest()

        // Also check for existing password credentials
        let passwordRequest = ASAuthorizationPasswordProvider().createRequest()

        return [appleIDRequest, passwordRequest]
    }
}

// MARK: - SwiftUI Coordinator

/// Coordinator for handling ASAuthorizationController delegate callbacks.
@MainActor
final class SignInWithAppleCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var completion: ((Result<ASAuthorization, Error>) -> Void)?

    func signIn(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion

        let requests = SignInWithAppleManager.shared.createRequests()
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion?(.success(authorization))
        completion = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window found")
        }
        return window
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow else {
            fatalError("No window found")
        }
        return window
        #endif
    }
}
