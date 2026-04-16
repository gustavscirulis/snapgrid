import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @EnvironmentObject var keySyncService: KeySyncService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if fileSystem.isAccessGranted {
                MainView()
            } else {
                ZStack {
                    Color.snapDarkBackground
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fileSystem.isAccessGranted)
        .onAppear {
            fileSystem.restoreAccess()
        }
        .task {
            for await granted in fileSystem.$isAccessGranted.values where granted {
                if let rootURL = fileSystem.rootURL {
                    keySyncService.checkForKeys(rootURL: rootURL)
                } else {
                    keySyncService.checkForSettingsKeys()
                }
                break
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if !fileSystem.isAccessGranted {
                    fileSystem.restoreAccess()
                }
                if !fileSystem.isUsingiCloud {
                    fileSystem.checkAndMigrateToiCloud(context: modelContext)
                }
                if let rootURL = fileSystem.rootURL {
                    keySyncService.checkForKeys(rootURL: rootURL)
                } else {
                    keySyncService.checkForSettingsKeys()
                }
            }
        }
        .onChange(of: fileSystem.isUsingiCloud) { _, usingiCloud in
            if usingiCloud, let rootURL = fileSystem.rootURL {
                keySyncService.checkForKeys(rootURL: rootURL)
            }
        }
    }
}
