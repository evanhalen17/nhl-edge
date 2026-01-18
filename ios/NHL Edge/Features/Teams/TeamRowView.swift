import SwiftUI

struct TeamRowView: View {
    let team: Team

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.headline)
                Text("\(team.conference) • \(team.division)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(team.abbrev)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    List { TeamRowView(team: MockData.teams[0]) }
}
