import SwiftUI

struct GameDetailView: View {
    let game: Game

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    teamBlock(
                        logoURL: game.awayLogoURL,
                        abbrev: game.awayAbbrev,
                        name: game.awayTeam,
                        alignment: .leading
                    )

                    Spacer()

                    VStack(spacing: 6) {
                        Text("AT")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !game.startTimeText.isEmpty {
                            Text(game.startTimeText)
                                .font(.headline)
                        } else {
                            Text(game.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                        }

                        if let venue = game.venue, !venue.isEmpty {
                            Text(venue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 180)

                    Spacer()

                    teamBlock(
                        logoURL: game.homeLogoURL,
                        abbrev: game.homeAbbrev,
                        name: game.homeTeam,
                        alignment: .trailing
                    )
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    detailRow(title: "Date", value: game.date.formatted(date: .long, time: .omitted))
                    detailRow(title: "Time", value: game.startTimeText.isEmpty
                              ? game.date.formatted(date: .omitted, time: .shortened)
                              : game.startTimeText)

                    if let venue = game.venue, !venue.isEmpty {
                        detailRow(title: "Venue", value: venue)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer(minLength: 12)
            }
            .padding(.top, 12)
        }
        .navigationTitle("\(game.awayAbbrev) @ \(game.homeAbbrev)")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func teamBlock(
        logoURL: String?,
        abbrev: String,
        name: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            FadingLogo(urlString: logoURL, boxSize: 56)
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.secondary.opacity(0.25), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            Text(abbrev)
                .font(.title3)
                .fontWeight(.bold)

            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: 140, alignment: alignment == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }
}

private struct FadingLogo: View {
    let urlString: String?
    let boxSize: CGFloat

    @State private var opacity: Double = 0
    private let fadeDuration: Double = 0.6

    var body: some View {
        SVGRemoteImageView(urlString: urlString, boxSize: boxSize) {
            withAnimation(.easeInOut(duration: fadeDuration)) {
                opacity = 1
            }
        }
        .opacity(opacity)
        .onAppear { opacity = 0 }
        .onChange(of: urlString) { _ in
            opacity = 0
        }
    }
}

#Preview {
    NavigationStack {
        GameDetailView(game: MockData.games[0])
    }
    .environmentObject(AppSettings())
}
