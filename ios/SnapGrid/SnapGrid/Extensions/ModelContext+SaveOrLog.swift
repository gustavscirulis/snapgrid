import SwiftData

extension ModelContext {
    /// Saves and logs failures instead of silently swallowing them.
    /// In DEBUG builds, triggers an assertion so developers notice immediately.
    func saveOrLog(file: String = #file, line: Int = #line) {
        do {
            try save()
        } catch {
            print("[SwiftData] Save failed at \(file):\(line): \(error)")
            #if DEBUG
            assertionFailure("SwiftData save failed: \(error)")
            #endif
        }
    }
}
