import Foundation

/// Reads the encrypted API key file from iCloud and decrypts it automatically.
/// Keys are held in memory only — never persisted to disk on iOS.
@MainActor
final class KeySyncService: ObservableObject {

    static let shared = KeySyncService()

    @Published private(set) var isUnlocked = false
    @Published private(set) var activeProvider: String?
    @Published private(set) var activeModel: String?

    private var decryptedKeys: [String: String] = [:]
    private let fileName = ".apikeys.encrypted"

    private init() {}

    /// Check for the encrypted key file and decrypt if found.
    /// Called on launch (when iCloud access is granted) and on every foreground transition.
    /// Skips entirely in local mode — encrypted key file only exists in iCloud.
    func checkForKeys(rootURL: URL) {
        guard FileSystemManager.shared?.isUsingiCloud == true else { return }

        let fileURL = rootURL.appendingPathComponent(fileName)
        let fm = FileManager.default

        print("[KeySync] Checking for keys at: \(fileURL.path)")

        // Handle iCloud placeholder — file not yet downloaded
        // iCloud placeholders for ".apikeys.encrypted" → ".apikeys.encrypted.icloud"
        if !fm.fileExists(atPath: fileURL.path) {
            let dir = fileURL.deletingLastPathComponent()
            // iCloud placeholder naming: prefix dot + original name + .icloud
            // For already-dotted files: .apikeys.encrypted → ..apikeys.encrypted.icloud
            // But also check without extra dot in case behavior varies
            let placeholderNames = [
                ".\(fileName).icloud",
                "\(fileName).icloud"
            ]

            var foundPlaceholder = false
            for name in placeholderNames {
                let placeholderURL = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: placeholderURL.path) {
                    try? fm.startDownloadingUbiquitousItem(at: fileURL)
                    print("[KeySync] Encrypted file is iCloud placeholder (\(name)), triggered download")
                    foundPlaceholder = true
                    break
                }
            }

            if !foundPlaceholder {
                print("[KeySync] No encrypted key file found at \(fileURL.path)")
            }

            // No file available yet
            isUnlocked = false
            activeProvider = nil
            activeModel = nil
            decryptedKeys = [:]
            return
        }

        do {
            let encrypted = try Data(contentsOf: fileURL)
            let decrypted = try KeySyncCrypto.decrypt(encrypted)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(KeySyncPayload.self, from: decrypted)

            decryptedKeys = payload.keys
            activeProvider = payload.provider
            activeModel = payload.model

            let hasAnyKey = payload.keys.values.contains { !$0.isEmpty }
            isUnlocked = hasAnyKey

            print("[KeySync] Decrypted keys — provider: \(payload.provider), keys: \(payload.keys.count)")
        } catch {
            print("[KeySync] Decryption failed: \(error.localizedDescription)")
            isUnlocked = false
            activeProvider = nil
            activeModel = nil
            decryptedKeys = [:]
        }
    }

    /// Get the API key for a specific provider.
    func apiKey(for provider: String) -> String? {
        decryptedKeys[provider]
    }

    /// Get the API key for the currently active provider.
    func activeAPIKey() -> String? {
        guard let provider = activeProvider else { return nil }
        return decryptedKeys[provider]
    }
}
