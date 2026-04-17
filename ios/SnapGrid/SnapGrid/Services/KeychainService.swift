import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.snapgrid.ios", category: "Keychain")

enum KeychainService {

    private static let serviceName = "com.snapgrid.apikeys"

    static func set(key: String, forService service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecAttrAccessGroup as String: "group.com.snapgrid"
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = Data(key.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed for \(service, privacy: .public): \(status)")
        }
    }

    static func get(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true,
            kSecAttrAccessGroup as String: "group.com.snapgrid"
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        if status != errSecItemNotFound {
            logger.error("Keychain read failed for \(service, privacy: .public): \(status)")
        }

        return nil
    }

    static func delete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecAttrAccessGroup as String: "group.com.snapgrid"
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed for \(service, privacy: .public): \(status)")
        }
    }

    static func exists(service: String) -> Bool {
        (try? get(service: service)) != nil
    }
}
