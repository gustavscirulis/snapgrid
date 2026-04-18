import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.snapgrid.ios", category: "KeySync")

enum KeySource: String {
    case settingsBundle
    case iCloudSync
    case none
}

@MainActor
final class KeySyncService: ObservableObject {

    static let shared = KeySyncService()
    private static let maskedPlaceholder = String(repeating: "•", count: 48)

    @Published private(set) var isUnlocked = false
    @Published private(set) var activeProvider: String?
    @Published private(set) var activeModel: String?
    @Published private(set) var keySource: KeySource = .none

    private var decryptedKeys: [String: String] = [:]
    private let fileName = ".apikeys.encrypted"

    private init() {}

    // MARK: - Main sync entry point

    func checkForKeys(rootURL: URL) {
        let defaults = UserDefaults.standard

        let sbApiKey = readAndClearSettingsBundleKey(defaults: defaults)
        let sbProvider = defaults.string(forKey: "settings_provider") ?? "none"
        let sbModel = (defaults.string(forKey: "settings_model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lastSyncedHash = defaults.string(forKey: "settings_lastSyncedKeyHash") ?? ""

        let providerIsNone = sbProvider == "none"
        let settingsBundleHasKey = !sbApiKey.isEmpty && !providerIsNone
        let currentHash = settingsBundleHasKey ? hashKey(sbApiKey) : ""
        let settingsBundleChanged = settingsBundleHasKey && currentHash != lastSyncedHash
        let settingsBundleCleared = providerIsNone && lastSyncedHash != ""

        if settingsBundleCleared {
            defaults.set("", forKey: "settings_lastSyncedKeyHash")
            clearKeychainKeys()
            if FileSystemManager.shared?.isUsingiCloud == true {
                writeToiCloud(rootURL: rootURL, provider: "none", model: "", keys: [:])
            }
            applyNoKeys()
            return
        }

        if settingsBundleChanged {
            guard AIProvider(rawValue: sbProvider) != nil else {
                logger.warning("Settings.bundle has unknown provider: \(sbProvider, privacy: .public)")
                applyNoKeys()
                return
            }

            saveKeyToKeychain(sbApiKey, provider: sbProvider)
            applyKeys(provider: sbProvider, model: sbModel.isEmpty ? nil : sbModel, keys: [sbProvider: sbApiKey], source: .settingsBundle)
            defaults.set(currentHash, forKey: "settings_lastSyncedKeyHash")

            if FileSystemManager.shared?.isUsingiCloud == true {
                writeToiCloud(rootURL: rootURL, provider: sbProvider, model: sbModel, keys: [sbProvider: sbApiKey])
            }
            return
        }

        if let payload = readiCloudPayload(rootURL: rootURL) {
            let iCloudActiveKey = payload.keys[payload.provider] ?? ""

            if payload.provider == "none" || iCloudActiveKey.isEmpty {
                if lastSyncedHash != "" {
                    defaults.set("", forKey: "settings_lastSyncedKeyHash")
                    defaults.set("none", forKey: "settings_provider")
                    clearKeychainKeys()
                }
                applyNoKeys()
                return
            }

            let iCloudHash = hashKey(iCloudActiveKey)
            if iCloudHash != lastSyncedHash {
                for (provider, key) in payload.keys {
                    saveKeyToKeychain(key, provider: provider)
                }
                applyKeys(provider: payload.provider, model: payload.model, keys: payload.keys, source: .iCloudSync)
                defaults.set(iCloudHash, forKey: "settings_lastSyncedKeyHash")
                defaults.set(payload.provider, forKey: "settings_provider")
                defaults.set(payload.model, forKey: "settings_model")
                defaults.set(Self.maskedPlaceholder, forKey: "settings_apiKey")
                return
            }

            applyKeys(provider: payload.provider, model: payload.model, keys: payload.keys, source: .iCloudSync)
            return
        }

        if settingsBundleHasKey, AIProvider(rawValue: sbProvider) != nil {
            let keychainKey = try? KeychainService.get(service: sbProvider)
            let effectiveKey = keychainKey ?? sbApiKey
            if !effectiveKey.isEmpty {
                applyKeys(provider: sbProvider, model: sbModel.isEmpty ? nil : sbModel, keys: [sbProvider: effectiveKey], source: .settingsBundle)
                return
            }
        }

        if let provider = loadKeysFromKeychain() {
            return
        }

        applyNoKeys()
    }

    func checkForSettingsKeys() {
        let defaults = UserDefaults.standard
        let sbApiKey = readAndClearSettingsBundleKey(defaults: defaults)
        let sbProvider = defaults.string(forKey: "settings_provider") ?? "none"
        let sbModel = (defaults.string(forKey: "settings_model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sbApiKey.isEmpty, sbProvider != "none", AIProvider(rawValue: sbProvider) != nil else {
            if loadKeysFromKeychain() != nil { return }
            applyNoKeys()
            return
        }

        saveKeyToKeychain(sbApiKey, provider: sbProvider)
        applyKeys(provider: sbProvider, model: sbModel.isEmpty ? nil : sbModel, keys: [sbProvider: sbApiKey], source: .settingsBundle)
    }

    // MARK: - Key accessors

    func apiKey(for provider: String) -> String? {
        decryptedKeys[provider]
    }

    func activeAPIKey() -> String? {
        guard let provider = activeProvider else { return nil }
        return decryptedKeys[provider]
    }

    // MARK: - Private helpers

    private func readAndClearSettingsBundleKey(defaults: UserDefaults) -> String {
        let key = (defaults.string(forKey: "settings_apiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if key == Self.maskedPlaceholder || key.isEmpty {
            return ""
        }
        defaults.set(Self.maskedPlaceholder, forKey: "settings_apiKey")
        return key
    }

    private func hashKey(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func saveKeyToKeychain(_ key: String, provider: String) {
        try? KeychainService.set(key: key, forService: provider)
    }

    private func clearKeychainKeys() {
        for provider in AIProvider.allCases {
            try? KeychainService.delete(service: provider.rawValue)
        }
    }

    @discardableResult
    private func loadKeysFromKeychain() -> String? {
        for provider in AIProvider.allCases {
            if let key = try? KeychainService.get(service: provider.rawValue), !key.isEmpty {
                applyKeys(provider: provider.rawValue, model: nil, keys: [provider.rawValue: key], source: .settingsBundle)
                return provider.rawValue
            }
        }
        return nil
    }

    private func applyKeys(provider: String, model: String?, keys: [String: String], source: KeySource) {
        decryptedKeys = keys
        activeProvider = provider
        activeModel = model
        keySource = source
        isUnlocked = keys.values.contains { !$0.isEmpty }
        logger.info("Using \(source.rawValue, privacy: .public) keys — provider: \(provider, privacy: .private)")
    }

    private func applyNoKeys() {
        decryptedKeys = [:]
        activeProvider = nil
        activeModel = nil
        keySource = .none
        isUnlocked = false
    }

    private func readiCloudPayload(rootURL: URL) -> KeySyncPayload? {
        let fileURL = rootURL.appendingPathComponent(fileName)
        let fm = FileManager.default

        if !fm.fileExists(atPath: fileURL.path) {
            let dir = fileURL.deletingLastPathComponent()
            let placeholderNames = [
                ".\(fileName).icloud",
                "\(fileName).icloud"
            ]
            for name in placeholderNames {
                let placeholderURL = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: placeholderURL.path) {
                    try? fm.startDownloadingUbiquitousItem(at: fileURL)
                    logger.info("Encrypted file is iCloud placeholder, triggered download")
                    break
                }
            }
            return nil
        }

        do {
            let encrypted = try Data(contentsOf: fileURL)
            let decrypted = try KeySyncCrypto.decrypt(encrypted)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(KeySyncPayload.self, from: decrypted)
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func writeToiCloud(rootURL: URL, provider: String, model: String, keys: [String: String]) {
        let payload = KeySyncPayload(
            provider: provider,
            model: model,
            keys: keys,
            updatedAt: .now
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(payload)
            let encrypted = try KeySyncCrypto.encrypt(plaintext)
            let fileURL = rootURL.appendingPathComponent(fileName)
            try encrypted.write(to: fileURL, options: .atomic)
            logger.info("Wrote keys to iCloud — provider: \(provider, privacy: .private)")
        } catch {
            logger.error("Failed to write to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }
}
