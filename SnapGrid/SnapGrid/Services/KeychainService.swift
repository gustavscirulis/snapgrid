import Foundation

enum KeychainService {

    /// Stores API keys in a JSON file inside Application Support.
    /// Avoids macOS Keychain password prompts that occur with
    /// "Sign to Run Locally" code signing.
    private static let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".keys.json")
    }()

    nonisolated(unsafe) private static var cache: [String: String]?
    nonisolated(unsafe) private static let lock = NSLock()

    private static func loadStore() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }

        if let cache { return cache }

        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = dict
        return dict
    }

    private static func saveStore(_ store: [String: String]) {
        lock.lock()
        cache = store
        lock.unlock()

        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storageURL, options: .atomic)
            // Restrict file permissions to owner only
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        }
    }

    static func set(key: String, forService service: String) throws {
        var store = loadStore()
        store[service] = key
        saveStore(store)
    }

    static func get(service: String) throws -> String? {
        loadStore()[service]
    }

    static func delete(service: String) throws {
        var store = loadStore()
        store.removeValue(forKey: service)
        saveStore(store)
    }

    static func exists(service: String) -> Bool {
        loadStore()[service] != nil
    }
}
