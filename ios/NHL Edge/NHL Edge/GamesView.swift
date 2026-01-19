import SwiftUI

struct GamesView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var games: [Game] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading games…")
                } else if let errorText {
                    ContentUnavailableView(
                        "Couldn’t load games",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText)
                    )
                } else {
                    List(games) { game in
                        NavigationLink(value: game) {
                            GameRowView(game: game)
                        }
                    }
                }
            }
            .navigationTitle("Games")
            .navigationDestination(for: Game.self) { game in
                GameDetailView(game: game)
            }
            .task { await load() }
            .refreshable { await load(forceRefreshTeams: false) }
        }
    }

    @MainActor
    private func load(forceRefreshTeams: Bool = false) async {
        errorText = nil

        if settings.useTestData {
            games = MockData.games
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 1) Get teams dictionary (prefer cache)
            let teamById: [Int: TeamDTO]
            if !forceRefreshTeams, let cached = SupabaseService.shared.getCachedTeamsById() {
                teamById = cached
            } else {
                let teamDTOs = try await SupabaseService.shared.fetchTeams(forceRefresh: forceRefreshTeams)
                teamById = Dictionary(uniqueKeysWithValues: teamDTOs.map { ($0.team_id, $0) })
            }

            // 2) Fetch games
            let gameDTOs = try await SupabaseService.shared.fetchGames()

            // 3) Map to UI model with join
            let mapped = gameDTOs.map { Game(dto: $0, teamById: teamById) }

            // 4) Sort by start time
            games = mapped.sorted { $0.date < $1.date }

        } catch {
            print("❌ Supabase error:", error)
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    GamesView()
        .environmentObject(AppSettings())
}
