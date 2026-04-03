import Foundation
import CryptoKit

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

// MARK: - Encryption / decryption using a compiled-in key

enum KeySyncCrypto {

    // Derived AES-256 symmetric key — split into fragments and combined
    // via HKDF so no single literal exposes the full secret.
    nonisolated(unsafe) private static let symmetricKey: SymmetricKey = {
        let a: [UInt8] = [0x4A, 0x91, 0xD3, 0x17, 0xBB, 0x6E, 0xF0, 0x82]
        let b: [UInt8] = [0xC5, 0x3A, 0x08, 0x7D, 0xE4, 0x59, 0x1F, 0xA6]
        let c: [UInt8] = [0x72, 0xDE, 0x45, 0x9B, 0x03, 0xF8, 0x61, 0xCC]
        let d: [UInt8] = [0x8F, 0x24, 0xB7, 0x53, 0xEA, 0x10, 0x96, 0x4D]
        let ikm = Data(a + b + c + d)
        let info = Data("com.snapgrid.keysync.v1".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            info: info,
            outputByteCount: 32
        )
        return derived
    }()

    static func encrypt(_ payload: Data) throws -> Data {
        let sealed = try AES.GCM.seal(payload, using: symmetricKey)
        let envelope = EncryptedEnvelope(
            version: 1,
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
        guard envelope.version == 1 else {
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
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    enum KeySyncError: LocalizedError {
        case unsupportedVersion
        case corruptedData

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "Unsupported key sync format version"
            case .corruptedData: return "Key sync data is corrupted"
            }
        }
    }
}
