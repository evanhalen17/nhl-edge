import SwiftUI

struct GameDetailView: View {
    let game: Game

    var body: some View {
        List {
            Section("Matchup") {
                LabeledContent("Away", value: "\(game.awayTeam) (\(game.awayAbbrev))")
                LabeledContent("Home", value: "\(game.homeTeam) (\(game.homeAbbrev))")
            }

            Section("Time & Place") {
                LabeledContent("Start", value: game.startTimeText)
                if let venue = game.venue {
                    LabeledContent("Venue", value: venue)
                }
            }

            Section("Projection (placeholder)") {
                if let home = game.homeWinProb, let away = game.awayWinProb {
                    LabeledContent("Home win", value: "\(Int((home * 100).rounded()))%")
                    LabeledContent("Away win", value: "\(Int((away * 100).rounded()))%")
                } else {
                    Text("No projection loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("\(game.awayAbbrev) @ \(game.homeAbbrev)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { GameDetailView(game: MockData.games[0]) }
}
