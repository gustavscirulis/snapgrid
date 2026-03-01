import Foundation
import LocalAuthentication

/// Manager for biometric authentication (Face ID / Touch ID).
///
/// Usage:
/// ```swift
/// // Check availability
/// if BiometricAuthManager.shared.isAvailable {
///     let success = await BiometricAuthManager.shared.authenticate()
/// }
/// ```
final class BiometricAuthManager: Sendable {

    // MARK: - Singleton

    static let shared = BiometricAuthManager()

    private init() {}

    // MARK: - Properties

    /// Whether biometric authentication is available.
    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// The type of biometry available on this device.
    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// Human-readable name for the biometry type.
    var biometryName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Biometrics"
        @unknown default:
            return "Biometrics"
        }
    }

    /// SF Symbol name for the biometry type.
    var biometrySymbol: String {
        switch biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock"
        @unknown default:
            return "lock"
        }
    }

    // MARK: - Authentication

    /// Authenticate using biometrics.
    ///
    /// - Parameter reason: The reason shown to the user (default provided).
    /// - Returns: `true` if authentication succeeded.
    func authenticate(reason: String = "Sign in to your account") async -> Bool {
        let context = LAContext()

        // Allow fallback to device passcode
        context.localizedFallbackTitle = "Use Passcode"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    /// Authenticate with detailed error information.
    ///
    /// - Parameter reason: The reason shown to the user.
    /// - Returns: Result with success or specific error.
    func authenticateWithResult(reason: String = "Sign in to your account") async -> Result<Void, BiometricError> {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .failure(mapError(error))
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? .success(()) : .failure(.authenticationFailed)
        } catch let laError as LAError {
            return .failure(mapLAError(laError))
        } catch {
            return .failure(.unknown)
        }
    }

    // MARK: - Error Mapping

    private func mapError(_ error: NSError?) -> BiometricError {
        guard let error = error else { return .unknown }

        switch error.code {
        case LAError.biometryNotAvailable.rawValue:
            return .notAvailable
        case LAError.biometryNotEnrolled.rawValue:
            return .notEnrolled
        case LAError.biometryLockout.rawValue:
            return .lockout
        default:
            return .unknown
        }
    }

    private func mapLAError(_ error: LAError) -> BiometricError {
        switch error.code {
        case .userCancel:
            return .cancelled
        case .userFallback:
            return .fallbackRequested
        case .authenticationFailed:
            return .authenticationFailed
        case .biometryLockout:
            return .lockout
        default:
            return .unknown
        }
    }
}

// MARK: - Errors

/// Biometric authentication errors.
enum BiometricError: Error, LocalizedError {
    case notAvailable
    case notEnrolled
    case lockout
    case cancelled
    case fallbackRequested
    case authenticationFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notEnrolled:
            return "Please set up Face ID or Touch ID in Settings"
        case .lockout:
            return "Biometrics is locked. Please use your passcode."
        case .cancelled:
            return "Authentication was cancelled"
        case .fallbackRequested:
            return "User requested passcode entry"
        case .authenticationFailed:
            return "Authentication failed"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
