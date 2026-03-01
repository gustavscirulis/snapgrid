import Foundation
import Security

/// Secure storage manager using Keychain.
///
/// Usage:
/// ```swift
/// // Save
/// KeychainManager.shared.save("value", for: .userID)
///
/// // Get
/// let value = KeychainManager.shared.get(.userID)
///
/// // Delete
/// KeychainManager.shared.delete(.userID)
/// ```
final class KeychainManager: Sendable {

    // MARK: - Singleton

    static let shared = KeychainManager()

    private init() {}

    // MARK: - Keys

    /// Keys for stored values.
    enum Key: String, Sendable {
        case userID = "com.app.auth.userID"
        case userName = "com.app.auth.userName"
        case userEmail = "com.app.auth.userEmail"
        case authToken = "com.app.auth.token"
        case refreshToken = "com.app.auth.refreshToken"
    }

    // MARK: - Save

    /// Save a string value to Keychain.
    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        // Delete existing
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Save data to Keychain.
    @discardableResult
    func save(_ data: Data, for key: Key) -> Bool {
        // Delete existing
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Get

    /// Get a string value from Keychain.
    func get(_ key: Key) -> String? {
        guard let data = getData(key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Get data from Keychain.
    func getData(_ key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    // MARK: - Delete

    /// Delete a value from Keychain.
    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Clear all stored values.
    func clearAll() {
        for key in [Key.userID, .userName, .userEmail, .authToken, .refreshToken] {
            delete(key)
        }
    }

    // MARK: - Exists

    /// Check if a key exists in Keychain.
    func exists(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - Codable Support

extension KeychainManager {

    /// Save an Encodable value to Keychain.
    func save<T: Encodable>(_ value: T, for key: Key) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else {
            return false
        }
        return save(data, for: key)
    }

    /// Get a Decodable value from Keychain.
    func get<T: Decodable>(_ key: Key, as type: T.Type) -> T? {
        guard let data = getData(key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
