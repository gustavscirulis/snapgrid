import SwiftUI
import SwiftData

@main
struct SnapGridApp: App {
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
            // Store is corrupted — delete and recreate
            print("[SnapGridApp] Store corrupted, recreating: \(error)")
            _ = DataCleanupService.deleteCorruptedStore()
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
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Images...") {
                    NotificationCenter.default.post(name: .importFiles, object: nil)
                }
                .keyboardShortcut("o")

                Button("Import from SnapGrid 1...") {
                    NotificationCenter.default.post(name: .importElectronLibrary, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Open Storage Location") {
                    NSWorkspace.shared.open(MediaStorageService.shared.baseURL)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Spaces") {
                Button("All") {
                    NotificationCenter.default.post(name: .switchToSpaceByIndex, object: nil, userInfo: ["digit": 1])
                }
                .keyboardShortcut("1")

                ForEach(2...9, id: \.self) { digit in
                    Button("Space \(digit - 1)") {
                        NotificationCenter.default.post(name: .switchToSpaceByIndex, object: nil, userInfo: ["digit": digit])
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(digit))))
                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .undoDelete, object: nil)
                }
                .keyboardShortcut("z")
            }
        }

        Settings {
            SettingsView()
        }
        .modelContainer(container)
    }
}

extension Notification.Name {
    static let importFiles = Notification.Name("importFiles")
    static let undoDelete = Notification.Name("undoDelete")
    static let apiKeySaved = Notification.Name("apiKeySaved")
    static let importElectronLibrary = Notification.Name("importElectronLibrary")
    static let willResetAllData = Notification.Name("willResetAllData")
    static let switchToSpaceByIndex = Notification.Name("switchToSpaceByIndex")
}
