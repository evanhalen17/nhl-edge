import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    Toggle("Use Test Data", isOn: $settings.useTestData)
                }
                Section("About") {
                    Text("Version 0.1")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

