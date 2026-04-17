import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.snapgrid", category: "Keychain")

enum KeychainService {

    private static let serviceName = "com.snapgrid.apikeys"

    nonisolated(unsafe) private static var cache: [String: String]?
    nonisolated(unsafe) private static let lock = NSLock()

    private static let legacyStorageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        return dir.appendingPathComponent(".keys.json")
    }()

    // MARK: - Public API

    static func set(key: String, forService service: String) throws {
        migrateIfNeeded()

        lock.lock()
        if cache == nil { cache = [:] }
        cache?[service] = key
        lock.unlock()

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed for \(service, privacy: .public): \(status)")
            fallbackSet(key: key, forService: service)
        }
    }

    static func get(service: String) throws -> String? {
        migrateIfNeeded()

        lock.lock()
        if let cached = cache?[service] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
            lock.lock()
            if cache == nil { cache = [:] }
            cache?[service] = value
            lock.unlock()
            return value
        }

        if status != errSecItemNotFound {
            logger.error("Keychain read failed for \(service, privacy: .public): \(status)")
        }

        return fallbackGet(service: service)
    }

    static func delete(service: String) throws {
        lock.lock()
        cache?.removeValue(forKey: service)
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed for \(service, privacy: .public): \(status)")
        }

        fallbackDelete(service: service)
    }

    static func exists(service: String) -> Bool {
        (try? get(service: service)) != nil
    }

    // MARK: - Migration from legacy .keys.json

    nonisolated(unsafe) private static var migrationDone = false

    private static func migrateIfNeeded() {
        guard !migrationDone else { return }
        migrationDone = true

        if UserDefaults.standard.bool(forKey: "keychainMigrationComplete_v1") { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyStorageURL.path),
              let data = try? Data(contentsOf: legacyStorageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            UserDefaults.standard.set(true, forKey: "keychainMigrationComplete_v1")
            return
        }

        logger.info("Migrating \(dict.count) keys from .keys.json to Keychain")

        var allSucceeded = true
        for (service, key) in dict {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: service,
                kSecValueData as String: Data(key.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: service
            ] as CFDictionary)
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status != errSecSuccess {
                logger.error("Migration failed for \(service, privacy: .public): \(status)")
                allSucceeded = false
            }

            lock.lock()
            if cache == nil { cache = [:] }
            cache?[service] = key
            lock.unlock()
        }

        if allSucceeded {
            try? fm.removeItem(at: legacyStorageURL)
        }
        UserDefaults.standard.set(true, forKey: "keychainMigrationComplete_v1")
    }

    // MARK: - File-based fallback for unsigned dev builds

    private static func fallbackGet(service: String) -> String? {
        guard let data = try? Data(contentsOf: legacyStorageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return dict[service]
    }

    private static func fallbackSet(key: String, forService service: String) {
        var dict: [String: String] = [:]
        if let data = try? Data(contentsOf: legacyStorageURL),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            dict = existing
        }
        dict[service] = key

        let dir = legacyStorageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: legacyStorageURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyStorageURL.path)
        }
    }

    private static func fallbackDelete(service: String) {
        guard let data = try? Data(contentsOf: legacyStorageURL),
              var dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        dict.removeValue(forKey: service)
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: legacyStorageURL, options: .atomic)
        }
    }
}
