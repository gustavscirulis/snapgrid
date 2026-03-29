import Foundation

/// Encrypts API key configuration and writes it to the shared iCloud container
/// so the iOS companion app can perform its own AI analysis.
enum KeySyncService {

    private static let fileName = ".apikeys.encrypted"

    /// Encrypt current key state and write to iCloud.
    /// Called automatically after every key save/remove and provider/model change.
    static func syncToiCloud() {
        guard MediaStorageService.shared.isUsingiCloud else { return }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)

        // Gather all configured keys
        var keys: [String: String] = [:]
        for provider in AIProvider.allCases {
            if let key = try? KeychainService.get(service: provider.keychainService), !key.isEmpty {
                keys[provider.rawValue] = key
            }
        }

        let currentProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? AIProvider.openai.rawValue
        let modelKey = "\(currentProvider)Model"
        let currentModel = UserDefaults.standard.string(forKey: modelKey) ?? "auto"

        let payload = KeySyncPayload(
            provider: currentProvider,
            model: currentModel,
            keys: keys,
            updatedAt: .now
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(payload)
            let encrypted = try KeySyncCrypto.encrypt(plaintext)
            try encrypted.write(to: url, options: .atomic)
            print("[KeySync] Wrote encrypted keys to iCloud")
        } catch {
            print("[KeySync] Failed to sync: \(error.localizedDescription)")
        }
    }

    /// Remove the encrypted file from iCloud (e.g. when user wants to revoke iOS access).
    static func removeSyncFile() {
        guard MediaStorageService.shared.isUsingiCloud else { return }
        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        print("[KeySync] Removed encrypted keys from iCloud")
    }
}
