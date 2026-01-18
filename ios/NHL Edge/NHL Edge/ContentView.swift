import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            GamesView()
                .tabItem { Label("Games", systemImage: "calendar") }

            TeamsView()
                .tabItem { Label("Teams", systemImage: "shield") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}

