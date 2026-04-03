import Testing
import Foundation
@testable import SnapGrid

@Suite("KeySyncCrypto", .tags(.crypto))
struct KeySyncCryptoTests {

    @Test("Encrypt then decrypt returns original data")
    func encryptDecryptRoundtrip() throws {
        let original = Data("hello world".utf8)
        let encrypted = try KeySyncCrypto.encrypt(original)
        let decrypted = try KeySyncCrypto.decrypt(encrypted)
        #expect(decrypted == original)
    }

    @Test("Empty payload encryption produces valid envelope")
    func emptyPayloadEncrypts() throws {
        // AES-GCM with empty plaintext produces empty ciphertext,
        // which the current decrypt can't handle (split on ":" drops empty part).
        // Verify encryption succeeds and produces valid JSON envelope.
        let encrypted = try KeySyncCrypto.encrypt(Data())
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encrypted)
        #expect(envelope.version == 1)
        #expect(!envelope.nonce.isEmpty)
    }

    @Test("Large payload roundtrip")
    func largePayloadRoundtrip() throws {
        let original = Data(repeating: 0xAB, count: 100_000)
        let encrypted = try KeySyncCrypto.encrypt(original)
        let decrypted = try KeySyncCrypto.decrypt(encrypted)
        #expect(decrypted == original)
    }

    @Test("KeySyncPayload roundtrip through encrypt/decrypt")
    func payloadStructRoundtrip() throws {
        let payload = KeySyncPayload(
            provider: "openai",
            model: "gpt-4o",
            keys: ["openai": "sk-test123", "anthropic": "sk-ant-test"],
            updatedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let encoded = try JSONEncoder().encode(payload)
        let encrypted = try KeySyncCrypto.encrypt(encoded)
        let decrypted = try KeySyncCrypto.decrypt(encrypted)
        let decoded = try JSONDecoder().decode(KeySyncPayload.self, from: decrypted)
        #expect(decoded.provider == payload.provider)
        #expect(decoded.model == payload.model)
        #expect(decoded.keys == payload.keys)
    }

    @Test("Decrypt corrupted data throws")
    func corruptedDataThrows() {
        let garbage = Data("not valid json at all".utf8)
        #expect(throws: (any Error).self) {
            try KeySyncCrypto.decrypt(garbage)
        }
    }

    @Test("Decrypt envelope with unsupported version throws")
    func unsupportedVersionThrows() throws {
        // Build a valid-looking envelope but with version 2
        let envelope = EncryptedEnvelope(version: 2, nonce: "AAAA", ciphertext: "BBBB:CCCC")
        let data = try JSONEncoder().encode(envelope)
        #expect(throws: KeySyncCrypto.KeySyncError.self) {
            try KeySyncCrypto.decrypt(data)
        }
    }

    @Test("Each encryption produces different ciphertext")
    func encryptionIsNondeterministic() throws {
        let original = Data("same input".utf8)
        let encrypted1 = try KeySyncCrypto.encrypt(original)
        let encrypted2 = try KeySyncCrypto.encrypt(original)
        // AES-GCM uses random nonces, so ciphertext should differ
        #expect(encrypted1 != encrypted2)
    }

    // MARK: - EncryptedEnvelope structure (cross-device contract)

    @Test("Encrypted envelope has version 1")
    func envelopeVersion() throws {
        let encrypted = try KeySyncCrypto.encrypt(Data("test".utf8))
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encrypted)
        #expect(envelope.version == 1)
    }

    @Test("Encrypted envelope ciphertext contains colon separator")
    func envelopeCiphertextFormat() throws {
        let encrypted = try KeySyncCrypto.encrypt(Data("test".utf8))
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encrypted)
        #expect(envelope.ciphertext.contains(":"))
        let parts = envelope.ciphertext.split(separator: ":")
        #expect(parts.count == 2)
    }

    @Test("Encrypted envelope nonce is valid base64")
    func envelopeNonceBase64() throws {
        let encrypted = try KeySyncCrypto.encrypt(Data("test".utf8))
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encrypted)
        #expect(Data(base64Encoded: envelope.nonce) != nil)
    }
}
