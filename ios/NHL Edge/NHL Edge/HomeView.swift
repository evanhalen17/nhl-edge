import SwiftUI

struct HomeView: View {
    private let games = MockData.games
    private let featuredTeams = Array(MockData.teams.prefix(4))

    var body: some View {
        NavigationStack {
            List {
                Section("Today's Games") {
                    if games.isEmpty {
                        Text("No games loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(games) { game in
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
            .navigationTitle("NHL")
            .navigationDestination(for: Game.self) { game in
                GameDetailView(game: game)
            }
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team)
            }
        }
    }
}

#Preview { HomeView() }

