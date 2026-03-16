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

            DeveloperSettingsTab()
                .tabItem {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 600, height: 450)
    }
}
