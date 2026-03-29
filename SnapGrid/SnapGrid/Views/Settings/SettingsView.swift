import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsTab()
                .tabItem {
                    Label("AI", systemImage: "brain")
                }

            GuidanceSettingsTab()
                .tabItem {
                    Label("Guidance", systemImage: "text.quote")
                }

            StorageSettingsTab()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive.connected.to.line.below")
                }

            #if DEBUG
            DeveloperSettingsTab()
                .tabItem {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
            #endif
        }
        .frame(width: 520, height: 460)
    }
}
