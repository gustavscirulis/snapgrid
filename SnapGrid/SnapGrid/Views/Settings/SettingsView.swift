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
        }
        .frame(width: 500, height: 400)
    }
}
