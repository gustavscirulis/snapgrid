import SwiftUI
import SwiftData

@main
struct SnapGridApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [MediaItem.self, Space.self, AnalysisResult.self])
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Images...") {
                    NotificationCenter.default.post(name: .importFiles, object: nil)
                }
                .keyboardShortcut("o")

                Button("Open Storage Location") {
                    NSWorkspace.shared.open(MediaStorageService.shared.baseURL)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
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
    }
}

extension Notification.Name {
    static let importFiles = Notification.Name("importFiles")
    static let undoDelete = Notification.Name("undoDelete")
    static let apiKeySaved = Notification.Name("apiKeySaved")
}
