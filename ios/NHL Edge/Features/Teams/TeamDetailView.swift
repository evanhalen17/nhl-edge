import SwiftUI

struct TeamDetailView: View {
    let team: Team

    var body: some View {
        List {
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

#Preview {
    NavigationStack { TeamDetailView(team: MockData.teams[0]) }
}
