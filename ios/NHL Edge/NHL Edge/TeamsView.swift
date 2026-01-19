import SwiftUI

struct TeamsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var teams: [Team] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading teams…")
                } else if let errorText {
                    ContentUnavailableView(
                        "Couldn’t load teams",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText)
                    )
                } else {
                    List(teams.sorted { $0.name < $1.name }) { team in
                        NavigationLink(value: team) {
                            TeamRowView(team: team)
                        }
                    }
                }
            }
            .navigationTitle("Teams")
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team)
            }
            .task { await load() }
            .refreshable { await load(forceRefresh: true) }
        }
    }

    @MainActor
    private func load(forceRefresh: Bool = false) async {
        errorText = nil

        if settings.useTestData {
            teams = MockData.teams
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let dtos = try await SupabaseService.shared.fetchTeams(forceRefresh: forceRefresh)
            teams = dtos.map(Team.init(dto:))
        } catch {
            print("❌ Supabase error:", error)
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    TeamsView()
        .environmentObject(AppSettings())
}
