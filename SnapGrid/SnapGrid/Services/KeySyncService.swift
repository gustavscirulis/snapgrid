import Foundation

enum KeySyncService {

    private static let fileName = ".apikeys.encrypted"
    private static let lastImportedAtKey = "keySyncLastImportedAt"

    // MARK: - Write local keys to iCloud

    static func syncToiCloud() {
        guard MediaStorageService.shared.isUsingiCloud else { return }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)

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
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastImportedAtKey)
            print("[KeySync] Wrote encrypted keys to iCloud")
        } catch {
            print("[KeySync] Failed to sync: \(error.localizedDescription)")
        }
    }

    // MARK: - Read keys from iCloud (written by iOS or another Mac)

    static func syncFromiCloud() {
        guard MediaStorageService.shared.isUsingiCloud else { return }

        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let encrypted = try Data(contentsOf: url)
            let decrypted = try KeySyncCrypto.decrypt(encrypted)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(KeySyncPayload.self, from: decrypted)

            let lastImported = UserDefaults.standard.double(forKey: lastImportedAtKey)
            let payloadTimestamp = payload.updatedAt.timeIntervalSince1970

            guard payloadTimestamp > lastImported else {
                print("[KeySync] iCloud file not newer than last import, skipping")
                return
            }

            if payload.provider == "none" {
                for provider in AIProvider.allCases {
                    try? KeychainService.delete(service: provider.keychainService)
                }
                UserDefaults.standard.set(payloadTimestamp, forKey: lastImportedAtKey)
                NotificationCenter.default.post(name: .apiKeySaved, object: nil)
                print("[KeySync] Imported key removal from iCloud")
                return
            }

            for (providerRaw, key) in payload.keys where !key.isEmpty {
                try KeychainService.set(key: key, forService: providerRaw)
            }

            UserDefaults.standard.set(payload.provider, forKey: "aiProvider")
            let modelKey = "\(payload.provider)Model"
            UserDefaults.standard.set(payload.model, forKey: modelKey)

            UserDefaults.standard.set(payloadTimestamp, forKey: lastImportedAtKey)

            NotificationCenter.default.post(name: .apiKeySaved, object: nil)
            print("[KeySync] Imported keys from iCloud — provider: \(payload.provider)")
        } catch {
            print("[KeySync] Failed to read from iCloud: \(error.localizedDescription)")
        }
    }

    // MARK: - Remove sync file

    static func removeSyncFile() {
        guard MediaStorageService.shared.isUsingiCloud else { return }
        let url = MediaStorageService.shared.baseURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        print("[KeySync] Removed encrypted keys from iCloud")
    }
}
