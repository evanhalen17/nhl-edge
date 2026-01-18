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
            .refreshable { await load() }
        }
    }

    @MainActor
    private func load() async {
        errorText = nil

        if settings.useTestData {
            games = MockData.games
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 1) Fetch teams and games from Supabase
            let teamDTOs = try await SupabaseService.shared.fetchTeams()
            let gameDTOs = try await SupabaseService.shared.fetchGames()

            // 2) Build lookup dictionary team_id -> TeamDTO
            let teamById: [Int: TeamDTO] = Dictionary(
                uniqueKeysWithValues: teamDTOs.map { ($0.team_id, $0) }
            )

            // 3) Map to UI model (resolving ids -> names/abbrevs)
            let mapped = gameDTOs.map { Game(dto: $0, teamById: teamById) }

            // Optional: sort by date/time
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
