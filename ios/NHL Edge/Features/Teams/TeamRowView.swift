import SwiftUI

struct TeamRowView: View {
    let team: Team
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Logo tile
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tileBackground)

                SVGRemoteImageView(
                    urlString: resolvedLogoURL,
                    boxSize: 32
                )
                .padding(1)
            }
            .frame(width: 44, height: 44)

            // Text
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

    // Dark tile for light-mode so "light" logos remain visible if they slip through,
    // and subtle tile for dark-mode.
    private var tileBackground: some ShapeStyle {
        colorScheme == .light ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.thinMaterial)
    }

    private var resolvedLogoURL: String? {
        guard let url = team.logoURL else { return nil }

        // NHL assets commonly provide both *_light.svg and *_dark.svg.
        // Use the appropriate variant for the current UI color scheme.
        if colorScheme == .light {
            return url
                .replacingOccurrences(of: "_light.svg", with: "_dark.svg")
        } else {
            return url
                .replacingOccurrences(of: "_dark.svg", with: "_light.svg")
        }
    }
}

#Preview {
    List {
        TeamRowView(team: MockData.teams[0])
    }
    .environmentObject(AppSettings())
}
