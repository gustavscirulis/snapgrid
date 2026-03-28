import SwiftUI
import SwiftData

@main
struct SnapGridApp: App {
    @StateObject private var fileSystem = FileSystemManager()
    let container: ModelContainer

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let snapGridDir = appSupport.appendingPathComponent("SnapGrid", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapGridDir, withIntermediateDirectories: true)
        let storeURL = snapGridDir.appendingPathComponent("default.store")

        do {
            let config = ModelConfiguration("SnapGrid", url: storeURL)
            container = try ModelContainer(for: MediaItem.self, Space.self, AnalysisResult.self, configurations: config)
        } catch {
            print("[SnapGridApp] Store corrupted, recreating: \(error)")
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove WAL/SHM files
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            do {
                let config = ModelConfiguration("SnapGrid", url: storeURL)
                container = try ModelContainer(for: MediaItem.self, Space.self, AnalysisResult.self, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer after recovery: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileSystem)
                .preferredColorScheme(.dark)
                .onAppear {
                    FileSystemManager.shared = fileSystem
                }
        }
        .modelContainer(container)
    }
}
