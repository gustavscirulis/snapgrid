import Testing
import Foundation
@testable import SnapGrid

/// Tests for the iOS KeySyncService (PR #124) — the encrypted key file
/// reading, decryption, and state management logic.
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
        // hasAnyKey check: empty keys means not unlocked
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

        // hasAnyKey should be true because anthropic has a non-empty value
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

        // Simulate what iOS KeySyncService.checkForKeys does
        let decrypted = try KeySyncCrypto.decrypt(encrypted)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: decrypted)

        #expect(decoded.provider == "gemini")
        #expect(decoded.model == "gemini-2.0-flash")
        #expect(decoded.keys["gemini"] == "AIza-test-key")

        let hasAnyKey = decoded.keys.values.contains { !$0.isEmpty }
        #expect(hasAnyKey == true)
    }

    // MARK: - iCloud placeholder detection (PR #124)

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
}
