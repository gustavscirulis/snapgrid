import SwiftUI
import SwiftData

@main
struct SnapGridApp: App {
    @StateObject private var fileSystem = FileSystemManager()
    @StateObject private var keySyncService = KeySyncService.shared
    let container: ModelContainer
    private static let multiSpaceStoreResetKey = "multiSpaceStoreReset_v1"

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "settings_provider": "none",
            "settings_apiKey": "",
            "settings_model": "auto"
        ])

        if !defaults.bool(forKey: "settings_defaults_v2") {
            if (defaults.string(forKey: "settings_model") ?? "").isEmpty {
                defaults.set("auto", forKey: "settings_model")
            }
            defaults.set(true, forKey: "settings_defaults_v2")
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let snapGridDir = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapGridDir, withIntermediateDirectories: true)
        let storeURL = snapGridDir.appendingPathComponent("default.store")

        if !UserDefaults.standard.bool(forKey: Self.multiSpaceStoreResetKey) {
            Self.deleteStoreFiles(at: storeURL)
            UserDefaults.standard.set(true, forKey: Self.multiSpaceStoreResetKey)
        }

        do {
            let config = ModelConfiguration("SnapGrid", url: storeURL)
            container = try ModelContainer(for: MediaItem.self, Space.self, AnalysisResult.self, configurations: config)
        } catch {
            print("[SnapGridApp] Store corrupted, recreating: \(error)")
            Self.deleteStoreFiles(at: storeURL)
            do {
                let config = ModelConfiguration("SnapGrid", url: storeURL)
                container = try ModelContainer(for: MediaItem.self, Space.self, AnalysisResult.self, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer after recovery: \(error)")
            }
        }
    }

    private static func deleteStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileSystem)
                .environmentObject(keySyncService)
                .preferredColorScheme(.dark)
                .onAppear {
                    FileSystemManager.shared = fileSystem
                }
        }
        .modelContainer(container)
    }
}
