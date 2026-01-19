import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var todayGames: [Game] = []
    @State private var featuredTeams: [Team] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if let errorText {
                    ContentUnavailableView(
                        "Couldn’t load home data",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText)
                    )
                } else {
                    List {
                        Section("Today's Games") {
                            if todayGames.isEmpty {
                                Text("No games today.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(todayGames) { game in
                                    NavigationLink(value: game) {
                                        GameRowView(game: game)
                                    }
                                }
                            }
                        }

                        Section("Featured Teams") {
                            ForEach(featuredTeams) { team in
                                NavigationLink(value: team) {
                                    TeamRowView(team: team)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("NHL")
            .navigationDestination(for: Game.self) { game in
                GameDetailView(game: game)
            }
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team)
            }
            .task { await load() }
            .refreshable { await load(forceRefreshTeams: true) }
        }
    }

    @MainActor
    private func load(forceRefreshTeams: Bool = false) async {
        errorText = nil

        if settings.useTestData {
            let allGames = MockData.games.sorted { $0.date < $1.date }
            todayGames = filterGamesForToday(allGames)
            featuredTeams = Array(MockData.teams.sorted { $0.name < $1.name }.prefix(6))
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 1) Teams (prefer cache unless forcing refresh)
            let teamById: [Int: TeamDTO]
            if !forceRefreshTeams, let cached = SupabaseService.shared.getCachedTeamsById() {
                teamById = cached
            } else {
                let teamDTOs = try await SupabaseService.shared.fetchTeams(forceRefresh: true)
                teamById = Dictionary(uniqueKeysWithValues: teamDTOs.map { ($0.team_id, $0) })
            }

            // 2) Games
            let gameDTOs = try await SupabaseService.shared.fetchGames()
            let allGames = gameDTOs
                .map { Game(dto: $0, teamById: teamById) }
                .sorted { $0.date < $1.date }

            todayGames = filterGamesForToday(allGames)

            // 3) Featured teams (simple for now: first 6 alphabetically)
            let teamDTOsForList = teamById.values.map { $0 }
            featuredTeams = Array(
                teamDTOsForList
                    .map(Team.init(dto:))
                    .sorted { $0.name < $1.name }
                    .prefix(6)
            )

        } catch {
            print("❌ Supabase error:", error)
            errorText = error.localizedDescription
        }
    }

    private func filterGamesForToday(_ games: [Game]) -> [Game] {
        let calendar = Calendar.current
        let today = Date()
        return games.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppSettings())
}
