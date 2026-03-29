import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @EnvironmentObject var keySyncService: KeySyncService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if fileSystem.isAccessGranted {
                MainView()
            } else if fileSystem.isCheckingAccess {
                ZStack {
                    Color.snapDarkBackground
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fileSystem.isAccessGranted)
        .onAppear {
            fileSystem.restoreAccess()
        }
        .task {
            // Wait for access to be granted, then check for synced API keys
            for await granted in fileSystem.$isAccessGranted.values where granted {
                if let rootURL = fileSystem.rootURL {
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
                if let rootURL = fileSystem.rootURL {
                    keySyncService.checkForKeys(rootURL: rootURL)
                }
            }
        }
        .onChange(of: fileSystem.isAccessGranted) { _, granted in
            if granted, let rootURL = fileSystem.rootURL {
                keySyncService.checkForKeys(rootURL: rootURL)
            }
        }
    }
}
