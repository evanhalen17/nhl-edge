import SwiftUI

struct GameRowView: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(game.awayAbbrev) @ \(game.homeAbbrev)")
                    .font(.headline)

                Text(game.startTimeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let venue = game.venue {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let home = game.homeWinProb, let away = game.awayWinProb {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Home \(Int((home * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Away \(Int((away * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    List { GameRowView(game: MockData.games[0]) }
}
