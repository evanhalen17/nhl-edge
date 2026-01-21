import SwiftUI

struct TeamDetailView: View {
    let team: Team

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    FadingLogo(urlString: team.logoURL, boxSize: 72)
                        .frame(width: 88, height: 88)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(team.name)
                            .font(.headline)

                        if !team.city.isEmpty {
                            Text(team.city)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(team.abbrev)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section("Team") {
                LabeledContent("Name", value: team.name)
                LabeledContent("Abbrev", value: team.abbrev)
                LabeledContent("City", value: team.city)
            }

            Section("Alignment") {
                LabeledContent("Conference", value: team.conference)
                LabeledContent("Division", value: team.division)
            }

            Section("Model (placeholder)") {
                if let rating = team.rating {
                    LabeledContent("Rating", value: String(format: "%.2f", rating))
                } else {
                    Text("No rating loaded yet.")
                        .foregroundStyle(.secondary)
                }

                if let odds = team.playoffOdds {
                    LabeledContent("Playoff odds", value: "\(Int((odds * 100).rounded()))%")
                } else {
                    Text("No playoff odds loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(team.abbrev)
        .navigationBarTitleDisplayMode(.inline)
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
    NavigationStack { TeamDetailView(team: MockData.teams[0]) }
}
