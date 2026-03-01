import SwiftUI
import AuthenticationServices

/// SwiftUI wrapper for Sign in with Apple button.
///
/// Usage:
/// ```swift
/// SignInWithAppleButtonView { result in
///     authManager.handleSignInWithApple(result)
/// }
/// ```
struct SignInWithAppleButtonView: View {

    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    @State private var coordinator = SignInWithAppleCoordinator()

    var body: some View {
        SignInWithAppleButton(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: onCompletion
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .cornerRadius(8)
    }
}

// MARK: - Custom Style Button

/// Custom styled Sign in with Apple button.
///
/// Use when you need more control over appearance.
struct CustomSignInWithAppleButton: View {

    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .semibold))

                Text("Sign in with Apple")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(colorScheme == .dark ? Color.white : Color.black)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Continue with Apple Button

/// "Continue with Apple" variant.
struct ContinueWithAppleButton: View {

    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(
            .continue,
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: onCompletion
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .cornerRadius(8)
    }
}

// MARK: - Biometric Sign In Button

/// Button for biometric authentication.
struct BiometricSignInButton: View {

    let onAuthenticate: () async -> Void

    private let biometricManager = BiometricAuthManager.shared

    var body: some View {
        if biometricManager.isAvailable {
            Button {
                Task {
                    await onAuthenticate()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: biometricManager.biometrySymbol)
                        .font(.system(size: 20))

                    Text("Sign in with \(biometricManager.biometryName)")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Previews

#Preview("Sign in with Apple") {
    VStack(spacing: 16) {
        SignInWithAppleButtonView { _ in }

        ContinueWithAppleButton { _ in }

        CustomSignInWithAppleButton { }

        BiometricSignInButton { }
    }
    .padding()
}
