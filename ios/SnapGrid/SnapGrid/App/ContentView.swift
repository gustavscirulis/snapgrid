import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                fileSystem.restoreAccess()
            }
        }
    }
}
