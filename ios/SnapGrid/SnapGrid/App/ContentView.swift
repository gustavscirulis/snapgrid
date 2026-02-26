import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fileSystem: FileSystemManager

    var body: some View {
        Group {
            if fileSystem.isAccessGranted {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fileSystem.isAccessGranted)
        .onAppear {
            fileSystem.restoreAccess()
        }
    }
}
