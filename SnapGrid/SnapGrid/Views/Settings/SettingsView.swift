import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SpacesSettingsTab()
                .tabItem {
                    Label("Spaces", systemImage: "square.grid.2x2")
                }

            #if DEBUG
            DeveloperSettingsTab()
                .tabItem {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
            #endif
        }
        .frame(width: 600, height: 450)
    }
}
