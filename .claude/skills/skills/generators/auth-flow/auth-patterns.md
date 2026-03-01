# Authentication Patterns and Best Practices

## Sign in with Apple

### How It Works

1. User taps "Sign in with Apple" button
2. System shows Apple ID authorization sheet
3. User authenticates (Face ID, Touch ID, or password)
4. User chooses to share or hide email
5. App receives user ID, name (first time only), and email

### Key Points

- **User ID is stable** - Same for your app across devices
- **Name only on first sign-in** - Store it immediately
- **Email can be private** - Apple provides relay address
- **Must handle revocation** - User can revoke access

### Credential State Check

Always check credential state on app launch:

```swift
func checkCredentialState(userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
    await withCheckedContinuation { continuation in
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
            continuation.resume(returning: state)
        }
    }
}

// On app launch
let state = await checkCredentialState(userID: savedUserID)
switch state {
case .authorized:
    // User is still signed in
case .revoked:
    // User revoked - sign them out
case .notFound:
    // User doesn't exist - sign them out
case .transferred:
    // Account transferred - handle migration
}
```

### Handling Name and Email

```swift
func handleAuthorization(_ authorization: ASAuthorization) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
        return
    }

    let userID = credential.user

    // Name is only provided on FIRST sign-in
    // Store it immediately!
    if let fullName = credential.fullName {
        let name = PersonNameComponentsFormatter().string(from: fullName)
        KeychainManager.shared.save(name, for: .userName)
    }

    // Email may be real or relay address
    if let email = credential.email {
        KeychainManager.shared.save(email, for: .userEmail)
    }

    // Always save user ID
    KeychainManager.shared.save(userID, for: .userID)
}
```

## Biometric Authentication

### Types

- **Face ID** - iPhone X and later, iPad Pro
- **Touch ID** - Older iPhones, MacBooks, Magic Keyboard

### Policy Types

```swift
// .deviceOwnerAuthenticationWithBiometrics
// - Only biometrics (Face ID or Touch ID)
// - Fails if not enrolled

// .deviceOwnerAuthentication
// - Biometrics with passcode fallback
// - More reliable, recommended for most apps
```

### Error Handling

```swift
func authenticate() async -> Bool {
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        switch error?.code {
        case LAError.biometryNotAvailable.rawValue:
            // Device doesn't support biometrics
        case LAError.biometryNotEnrolled.rawValue:
            // User hasn't set up Face ID/Touch ID
        case LAError.biometryLockout.rawValue:
            // Too many failed attempts
        default:
            break
        }
        return false
    }

    do {
        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Sign in to your account"
        )
    } catch let error as LAError {
        switch error.code {
        case .userCancel:
            // User cancelled
        case .userFallback:
            // User chose to enter password
        case .authenticationFailed:
            // Biometric didn't match
        default:
            break
        }
        return false
    }
}
```

### Biometry Type Detection

```swift
var biometryType: LABiometryType {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    return context.biometryType
}

// Use for UI
switch biometryType {
case .faceID:
    Image(systemName: "faceid")
    Text("Sign in with Face ID")
case .touchID:
    Image(systemName: "touchid")
    Text("Sign in with Touch ID")
case .opticID:
    Image(systemName: "opticid")
    Text("Sign in with Optic ID")  // visionOS
case .none:
    // Biometrics not available
}
```

## Keychain Storage

### Why Keychain?

- **Encrypted** - Data encrypted at rest
- **Persists** - Survives app reinstall
- **Shared** - Can share between apps (same team)
- **Secure Enclave** - Hardware-backed security

### Basic Operations

```swift
actor KeychainManager {
    func save(_ value: String, for key: KeychainKey) throws {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func get(_ key: KeychainKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### Access Control

```swift
// Require biometric authentication to read
let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    .biometryCurrentSet,  // Requires current biometry
    nil
)

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: key,
    kSecValueData as String: data,
    kSecAttrAccessControl as String: access as Any
]
```

## Session Management

### Token Storage

```swift
struct AuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}
```

### Auto-Refresh Pattern

```swift
actor SessionManager {
    private var token: AuthToken?
    private var refreshTask: Task<AuthToken, Error>?

    func validToken() async throws -> AuthToken {
        // Return valid token
        if let token = token, !token.isExpired {
            return token
        }

        // Join existing refresh if in progress
        if let refreshTask = refreshTask {
            return try await refreshTask.value
        }

        // Start refresh
        let task = Task {
            let newToken = try await refreshToken()
            self.token = newToken
            return newToken
        }

        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }
}
```

## Security Best Practices

### Do
- Store sensitive data in Keychain, not UserDefaults
- Validate credential state on every app launch
- Use `.deviceOwnerAuthentication` for reliability
- Handle revoked credentials gracefully
- Clear tokens on sign out

### Don't
- Store passwords in plain text
- Trust client-side validation alone
- Ignore authentication errors
- Keep tokens after sign out
- Skip credential state checks

## SwiftUI Integration

### Environment-Based Auth

```swift
@MainActor
@Observable
class AuthenticationManager {
    var isAuthenticated = false
    var currentUser: User?

    func signOut() {
        KeychainManager.shared.clearAll()
        isAuthenticated = false
        currentUser = nil
    }
}

// In App
@main
struct MyApp: App {
    @State private var authManager = AuthenticationManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                } else {
                    AuthenticationView()
                }
            }
            .environment(authManager)
        }
    }
}
```

### Auth State Handling

```swift
struct ContentView: View {
    @Environment(AuthenticationManager.self) var authManager

    var body: some View {
        NavigationStack {
            // Content
        }
        .task {
            // Check credential state on appear
            await authManager.checkCredentialState()
        }
    }
}
```
