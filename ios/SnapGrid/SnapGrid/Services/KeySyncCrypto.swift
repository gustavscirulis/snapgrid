import Foundation
import CryptoKit
import Security
import os

private let logger = Logger(subsystem: "com.snapgrid.ios", category: "KeySyncCrypto")

// MARK: - Encrypted envelope persisted to iCloud

struct EncryptedEnvelope: Codable {
    let version: Int
    let nonce: String   // base64
    let ciphertext: String // base64 (AES-GCM ciphertext + tag)
}

// MARK: - Plaintext payload inside the envelope

struct KeySyncPayload: Codable {
    let provider: String
    let model: String
    let keys: [String: String]
    let updatedAt: Date
}

// MARK: - Encryption / decryption

enum KeySyncCrypto {

    static func encrypt(_ payload: Data) throws -> Data {
        let key = try userKey()
        let sealed = try AES.GCM.seal(payload, using: key)
        let envelope = EncryptedEnvelope(
            version: 2,
            nonce: Data(sealed.nonce).base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString() + ":" +
                sealed.tag.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(envelope)
    }

    static func decrypt(_ data: Data) throws -> Data {
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)

        let key: SymmetricKey
        switch envelope.version {
        case 1:
            key = legacyKey
        case 2:
            key = try userKey()
        default:
            throw KeySyncError.unsupportedVersion
        }

        guard let nonceData = Data(base64Encoded: envelope.nonce) else {
            throw KeySyncError.corruptedData
        }

        let parts = envelope.ciphertext.split(separator: ":")
        guard parts.count == 2,
              let ciphertextData = Data(base64Encoded: String(parts[0])),
              let tagData = Data(base64Encoded: String(parts[1])) else {
            throw KeySyncError.corruptedData
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertextData,
            tag: tagData
        )
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Per-user key (stored in iCloud Keychain)

    private static func userKey() throws -> SymmetricKey {
        if let existing = loadKeyFromKeychain() {
            return deriveKey(from: existing)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        if storeKeyInKeychain(keyData, synchronizable: true) {
            return deriveKey(from: keyData)
        }

        if storeKeyInKeychain(keyData, synchronizable: false) {
            logger.warning("Stored encryption key locally only (iCloud Keychain unavailable)")
            return deriveKey(from: keyData)
        }

        throw KeySyncError.keychainUnavailable
    }

    private static func deriveKey(from ikm: Data) -> SymmetricKey {
        let info = Data("com.snapgrid.keysync.v2".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            info: info,
            outputByteCount: 32
        )
    }

    private static func loadKeyFromKeychain() -> Data? {
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.snapgrid.keysync",
            kSecAttrAccount as String: "encryption-key-v2",
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(syncQuery as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return data
        }

        let localQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.snapgrid.keysync",
            kSecAttrAccount as String: "encryption-key-v2",
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true
        ]

        var localResult: AnyObject?
        let localStatus = SecItemCopyMatching(localQuery as CFDictionary, &localResult)

        if localStatus == errSecSuccess, let data = localResult as? Data, data.count == 32 {
            return data
        }

        return nil
    }

    private static func storeKeyInKeychain(_ keyData: Data, synchronizable: Bool) -> Bool {
        let deleteSync: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.snapgrid.keysync",
            kSecAttrAccount as String: "encryption-key-v2",
            kSecAttrSynchronizable as String: true
        ]
        SecItemDelete(deleteSync as CFDictionary)

        let deleteLocal: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.snapgrid.keysync",
            kSecAttrAccount as String: "encryption-key-v2",
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(deleteLocal as CFDictionary)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.snapgrid.keysync",
            kSecAttrAccount as String: "encryption-key-v2",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: synchronizable
        ]

        if !synchronizable {
            query[kSecAttrAccessGroup as String] = "group.com.snapgrid"
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Legacy key (v1 — hardcoded, kept for migration only)

    private static let legacyKey: SymmetricKey = {
        let a: [UInt8] = [0x4A, 0x91, 0xD3, 0x17, 0xBB, 0x6E, 0xF0, 0x82]
        let b: [UInt8] = [0xC5, 0x3A, 0x08, 0x7D, 0xE4, 0x59, 0x1F, 0xA6]
        let c: [UInt8] = [0x72, 0xDE, 0x45, 0x9B, 0x03, 0xF8, 0x61, 0xCC]
        let d: [UInt8] = [0x8F, 0x24, 0xB7, 0x53, 0xEA, 0x10, 0x96, 0x4D]
        let ikm = Data(a + b + c + d)
        let info = Data("com.snapgrid.keysync.v1".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            info: info,
            outputByteCount: 32
        )
    }()

    // MARK: - Test support

    static func encrypt(_ payload: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(payload, using: key)
        let envelope = EncryptedEnvelope(
            version: 2,
            nonce: Data(sealed.nonce).base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString() + ":" +
                sealed.tag.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(envelope)
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
        guard envelope.version == 1 || envelope.version == 2 else {
            throw KeySyncError.unsupportedVersion
        }

        guard let nonceData = Data(base64Encoded: envelope.nonce) else {
            throw KeySyncError.corruptedData
        }

        let parts = envelope.ciphertext.split(separator: ":")
        guard parts.count == 2,
              let ciphertextData = Data(base64Encoded: String(parts[0])),
              let tagData = Data(base64Encoded: String(parts[1])) else {
            throw KeySyncError.corruptedData
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertextData,
            tag: tagData
        )
        return try AES.GCM.open(sealedBox, using: key)
    }

    enum KeySyncError: LocalizedError {
        case unsupportedVersion
        case corruptedData
        case keychainUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "Unsupported key sync format version"
            case .corruptedData: return "Key sync data is corrupted"
            case .keychainUnavailable: return "Cannot access Keychain for encryption key storage"
            }
        }
    }
}
