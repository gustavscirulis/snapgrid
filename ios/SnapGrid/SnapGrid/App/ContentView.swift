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
            // Wait for access to be granted, then check for synced API keys
            for await granted in fileSystem.$isAccessGranted.values where granted {
                if fileSystem.isUsingiCloud, let rootURL = fileSystem.rootURL {
                    keySyncService.checkForKeys(rootURL: rootURL)
                }
                break
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if !fileSystem.isAccessGranted {
                    fileSystem.restoreAccess()
                }
                // Silently check for iCloud availability when in local mode
                if !fileSystem.isUsingiCloud {
                    fileSystem.checkAndMigrateToiCloud(context: modelContext)
                }
                if fileSystem.isUsingiCloud, let rootURL = fileSystem.rootURL {
                    keySyncService.checkForKeys(rootURL: rootURL)
                }
            }
        }
        .onChange(of: fileSystem.isUsingiCloud) { _, usingiCloud in
            // When we switch to iCloud (after migration), sync keys
            if usingiCloud, let rootURL = fileSystem.rootURL {
                keySyncService.checkForKeys(rootURL: rootURL)
            }
        }
    }
}
