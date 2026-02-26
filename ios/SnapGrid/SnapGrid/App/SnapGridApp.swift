import SwiftUI

@main
struct SnapGridApp: App {
    @StateObject private var fileSystem = FileSystemManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileSystem)
                .preferredColorScheme(.dark)
        }
    }
}
