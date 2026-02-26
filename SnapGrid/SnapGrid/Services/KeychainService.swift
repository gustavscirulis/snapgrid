import Foundation

enum KeychainService {

    private static let storagePrefix = "com.snapgrid.apikey."

    static func set(key: String, forService service: String) throws {
        UserDefaults.standard.set(key, forKey: storagePrefix + service)
    }

    static func get(service: String) throws -> String? {
        UserDefaults.standard.string(forKey: storagePrefix + service)
    }

    static func delete(service: String) throws {
        UserDefaults.standard.removeObject(forKey: storagePrefix + service)
    }

    static func exists(service: String) -> Bool {
        UserDefaults.standard.string(forKey: storagePrefix + service) != nil
    }
}
