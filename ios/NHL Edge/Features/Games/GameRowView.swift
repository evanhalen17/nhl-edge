import SwiftUI

struct GameRowView: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            // Away team
            HStack(spacing: 8) {
                logo(urlString: game.awayLogoURL)

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.awayAbbrev)
                        .font(.headline)
                    Text(game.awayTeam)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !game.startTimeText.isEmpty {
                    Text(game.startTimeText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    Text(game.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                if let venue = game.venue, !venue.isEmpty {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)

            Spacer()

            // Home team
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(game.homeAbbrev)
                        .font(.headline)
                    Text(game.homeTeam)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                logo(urlString: game.homeLogoURL)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func logo(urlString: String?) -> some View {
        SVGRemoteImageView(urlString: urlString, boxSize: 32)
            .frame(width: 40, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.secondary.opacity(0.25), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    List {
        GameRowView(game: MockData.games[0])
        GameRowView(game: MockData.games[1])
    }
    .environmentObject(AppSettings())
}
