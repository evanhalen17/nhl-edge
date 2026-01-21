import SwiftUI

struct TeamRowView: View {
    let team: Team

    var body: some View {
        HStack(spacing: 12) {
            SVGRemoteImageView(urlString: team.logoURL, boxSize: 32)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.secondary.opacity(0.25), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.headline)
                    .lineLimit(1)

                if !team.city.isEmpty {
                    Text(team.city)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
    List {
        TeamRowView(team: MockData.teams[0])
    }
    .environmentObject(AppSettings())
}
