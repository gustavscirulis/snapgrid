import Foundation

enum KeySource: String {
    case settingsBundle
    case iCloudSync
    case none
}

@MainActor
final class KeySyncService: ObservableObject {

    static let shared = KeySyncService()

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
        let sbApiKey = (defaults.string(forKey: "settings_apiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sbProvider = defaults.string(forKey: "settings_provider") ?? "anthropic"
        let sbModel = (defaults.string(forKey: "settings_model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lastSyncedKey = defaults.string(forKey: "settings_lastSyncedApiKey") ?? ""

        let providerIsNone = sbProvider == "none"
        let settingsBundleHasKey = !sbApiKey.isEmpty && !providerIsNone
        let settingsBundleChanged = settingsBundleHasKey && sbApiKey != lastSyncedKey
        let settingsBundleCleared = providerIsNone && lastSyncedKey != ""

        if settingsBundleCleared {
            defaults.set("", forKey: "settings_lastSyncedApiKey")
            defaults.set("", forKey: "settings_apiKey")
            if FileSystemManager.shared?.isUsingiCloud == true {
                writeToiCloud(rootURL: rootURL, provider: "none", model: "", keys: [:])
            }
            applyNoKeys()
            return
        }

        if settingsBundleChanged {
            guard AIProvider(rawValue: sbProvider) != nil else {
                print("[KeySync] Settings.bundle has unknown provider: \(sbProvider)")
                applyNoKeys()
                return
            }

            applyKeys(provider: sbProvider, model: sbModel.isEmpty ? nil : sbModel, keys: [sbProvider: sbApiKey], source: .settingsBundle)
            defaults.set(sbApiKey, forKey: "settings_lastSyncedApiKey")

            if FileSystemManager.shared?.isUsingiCloud == true {
                writeToiCloud(rootURL: rootURL, provider: sbProvider, model: sbModel, keys: [sbProvider: sbApiKey])
            }
            return
        }

        if let payload = readiCloudPayload(rootURL: rootURL) {
            let iCloudActiveKey = payload.keys[payload.provider] ?? ""

            if payload.provider == "none" || iCloudActiveKey.isEmpty {
                if lastSyncedKey != "" {
                    defaults.set("", forKey: "settings_lastSyncedApiKey")
                    defaults.set("", forKey: "settings_apiKey")
                    defaults.set("none", forKey: "settings_provider")
                }
                applyNoKeys()
                return
            }

            if iCloudActiveKey != lastSyncedKey {
                applyKeys(provider: payload.provider, model: payload.model, keys: payload.keys, source: .iCloudSync)
                defaults.set(iCloudActiveKey, forKey: "settings_lastSyncedApiKey")
                defaults.set(iCloudActiveKey, forKey: "settings_apiKey")
                defaults.set(payload.provider, forKey: "settings_provider")
                defaults.set(payload.model, forKey: "settings_model")
                return
            }

            applyKeys(provider: payload.provider, model: payload.model, keys: payload.keys, source: .iCloudSync)
            return
        }

        if settingsBundleHasKey, AIProvider(rawValue: sbProvider) != nil {
            applyKeys(provider: sbProvider, model: sbModel.isEmpty ? nil : sbModel, keys: [sbProvider: sbApiKey], source: .settingsBundle)
            return
        }

        applyNoKeys()
    }

    func checkForSettingsKeys() {
        let defaults = UserDefaults.standard
        let sbApiKey = (defaults.string(forKey: "settings_apiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sbProvider = defaults.string(forKey: "settings_provider") ?? "anthropic"
        let sbModel = (defaults.string(forKey: "settings_model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sbApiKey.isEmpty, sbProvider != "none", AIProvider(rawValue: sbProvider) != nil else {
            applyNoKeys()
            return
        }

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

    private func applyKeys(provider: String, model: String?, keys: [String: String], source: KeySource) {
        decryptedKeys = keys
        activeProvider = provider
        activeModel = model
        keySource = source
        isUnlocked = keys.values.contains { !$0.isEmpty }
        print("[KeySync] Using \(source.rawValue) keys — provider: \(provider)")
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
                    print("[KeySync] Encrypted file is iCloud placeholder, triggered download")
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
            print("[KeySync] Decryption failed: \(error.localizedDescription)")
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
            print("[KeySync] Wrote keys to iCloud — provider: \(provider)")
        } catch {
            print("[KeySync] Failed to write to iCloud: \(error.localizedDescription)")
        }
    }
}
