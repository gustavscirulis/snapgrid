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
                SpacesMenuContent()
                    .modelContainer(container)

                Divider()

                Button("New Space") {
                    NotificationCenter.default.post(name: .createNewSpace, object: nil)
                }
                .keyboardShortcut("n")
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Paste") {
                    if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSText {
                        firstResponder.tryToPerform(#selector(NSText.paste(_:)), with: nil)
                    } else {
                        NotificationCenter.default.post(name: .pasteImages, object: nil)
                    }
                }
                .keyboardShortcut("v")

                Button("Find") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f")

                Button("Select All") {
                    // If a text field is focused (e.g. search), do standard text select all;
                    // otherwise select all grid images
                    if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSText {
                        firstResponder.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
                    } else {
                        NotificationCenter.default.post(name: .selectAll, object: nil)
                    }
                }
                .keyboardShortcut("a")
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .undoDelete, object: nil)
                }
                .keyboardShortcut("z")

                Button("Delete") {
                    NotificationCenter.default.post(name: .deleteSelected, object: nil)
                }
                .keyboardShortcut(.delete)
            }
        }

        Settings {
            SettingsView()
        }
        .modelContainer(container)
    }
}

private struct SpacesMenuContent: View {
    @Query(sort: \Space.order) private var spaces: [Space]

    var body: some View {
        Button("All") {
            NotificationCenter.default.post(name: .switchToSpaceByIndex, object: nil, userInfo: ["digit": 1])
        }
        .keyboardShortcut("1")

        ForEach(Array(spaces.prefix(8).enumerated()), id: \.element.id) { index, space in
            Button(space.name) {
                NotificationCenter.default.post(name: .switchToSpaceByIndex, object: nil, userInfo: ["digit": index + 2])
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 2))))
        }
    }
}

extension Notification.Name {
    static let importFiles = Notification.Name("importFiles")
    static let undoDelete = Notification.Name("undoDelete")
    static let apiKeySaved = Notification.Name("apiKeySaved")
    static let importElectronLibrary = Notification.Name("importElectronLibrary")
    static let willResetAllData = Notification.Name("willResetAllData")
    static let switchToSpaceByIndex = Notification.Name("switchToSpaceByIndex")
    static let createNewSpace = Notification.Name("createNewSpace")
    static let focusSearch = Notification.Name("focusSearch")
    static let selectAll = Notification.Name("selectAll")
    static let pasteImages = Notification.Name("pasteImages")
    static let deleteSelected = Notification.Name("deleteSelected")
    static let analysisCompleted = Notification.Name("analysisCompleted")
}
