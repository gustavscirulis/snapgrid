import Testing
import Foundation
@testable import SnapGrid

@Suite("KeySyncService", .tags(.crypto))
struct KeySyncServiceTests {

    // MARK: - KeySyncPayload roundtrip

    @Test("KeySyncPayload encodes all fields")
    func payloadEncode() throws {
        let payload = KeySyncPayload(
            provider: "anthropic",
            model: "claude-sonnet-4-5",
            keys: ["anthropic": "sk-ant-test", "openai": "sk-test"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["provider"] as? String == "anthropic")
        #expect(json?["model"] as? String == "claude-sonnet-4-5")
        let keys = json?["keys"] as? [String: String]
        #expect(keys?["anthropic"] == "sk-ant-test")
        #expect(keys?["openai"] == "sk-test")
    }

    @Test("KeySyncPayload decode roundtrip")
    func payloadRoundtrip() throws {
        let original = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "sk-123"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        #expect(decoded.provider == "openai")
        #expect(decoded.model == "gpt-4o")
        #expect(decoded.keys["openai"] == "sk-123")
    }

    @Test("KeySyncPayload with empty keys dict")
    func emptyKeys() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: [:],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        #expect(decoded.keys.isEmpty)
        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == false)
    }

    @Test("KeySyncPayload with empty string values")
    func emptyStringValues() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "", "anthropic": "sk-valid"],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == true)
    }

    @Test("KeySyncPayload all empty string values means not unlocked")
    func allEmptyStringValues() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "", "anthropic": ""],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: data)

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == false)
    }

    // MARK: - Full encrypt/decrypt/decode pipeline

    @Test("End-to-end: encrypt payload, decrypt, decode")
    func endToEndPipeline() throws {
        let payload = KeySyncPayload(
            provider: "gemini",
            model: "gemini-2.0-flash",
            keys: ["gemini": "AIza-test-key"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoded = try JSONEncoder().encode(payload)
        let encrypted = try KeySyncCrypto.encrypt(encoded)

        let decrypted = try KeySyncCrypto.decrypt(encrypted)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: decrypted)

        #expect(decoded.provider == "gemini")
        #expect(decoded.model == "gemini-2.0-flash")
        #expect(decoded.keys["gemini"] == "AIza-test-key")

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == true)
    }

    // MARK: - iCloud placeholder detection

    @Test("iCloud placeholder names for dotted files")
    func iCloudPlaceholderNames() {
        let fileName = ".apikeys.encrypted"
        let placeholderNames = [
            ".\(fileName).icloud",
            "\(fileName).icloud"
        ]
        #expect(placeholderNames[0] == "..apikeys.encrypted.icloud")
        #expect(placeholderNames[1] == ".apikeys.encrypted.icloud")
    }

    // MARK: - Settings.bundle key reading

    @Test("Settings.bundle non-empty key unlocks service")
    @MainActor func settingsBundleUnlocks() async {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: "settings_apiKey")
            defaults.removeObject(forKey: "settings_provider")
            defaults.removeObject(forKey: "settings_model")
            defaults.removeObject(forKey: "settings_lastSyncedApiKey")
        }

        defaults.set("sk-ant-test123", forKey: "settings_apiKey")
        defaults.set("anthropic", forKey: "settings_provider")
        defaults.set("", forKey: "settings_model")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == true)
        #expect(service.keySource == .settingsBundle)
        #expect(service.activeProvider == "anthropic")
        #expect(service.activeModel == nil)
        #expect(service.activeAPIKey() == "sk-ant-test123")
    }

    @Test("Settings.bundle empty key does not unlock")
    @MainActor func settingsBundleEmptyKey() async {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: "settings_apiKey")
            defaults.removeObject(forKey: "settings_provider")
        }

        defaults.set("", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Settings.bundle whitespace-only key treated as empty")
    @MainActor func settingsBundleWhitespaceKey() async {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: "settings_apiKey")
            defaults.removeObject(forKey: "settings_provider")
        }

        defaults.set("   ", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Settings.bundle unknown provider is rejected")
    @MainActor func settingsBundleUnknownProvider() async {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: "settings_apiKey")
            defaults.removeObject(forKey: "settings_provider")
        }

        defaults.set("sk-test123", forKey: "settings_apiKey")
        defaults.set("invalid_provider", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }

    @Test("Settings.bundle with model sets activeModel")
    @MainActor func settingsBundleWithModel() async {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: "settings_apiKey")
            defaults.removeObject(forKey: "settings_provider")
            defaults.removeObject(forKey: "settings_model")
            defaults.removeObject(forKey: "settings_lastSyncedApiKey")
        }

        defaults.set("sk-test123", forKey: "settings_apiKey")
        defaults.set("openai", forKey: "settings_provider")
        defaults.set("gpt-4o-mini", forKey: "settings_model")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == true)
        #expect(service.activeModel == "gpt-4o-mini")
    }

    @Test("Settings.bundle provider 'none' does not unlock")
    @MainActor func settingsBundleNoneProvider() async {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: "settings_apiKey")
            defaults.removeObject(forKey: "settings_provider")
        }

        defaults.set("sk-test123", forKey: "settings_apiKey")
        defaults.set("none", forKey: "settings_provider")

        let service = KeySyncService.shared
        service.checkForSettingsKeys()

        #expect(service.isUnlocked == false)
        #expect(service.keySource == .none)
    }
}
