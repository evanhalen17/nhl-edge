import Foundation

enum MockData {
    static let games: [Game] = [
        Game(
            id: UUID().uuidString,
            date: Date(),
            awayTeam: "New Jersey Devils",
            homeTeam: "New York Rangers",
            awayAbbrev: "NJD",
            homeAbbrev: "NYR",
            startTimeText: "7:00 PM",
            venue: "Madison Square Garden",
            awayLogoURL: nil,
            homeLogoURL: nil,
            homeWinProb: nil,
            awayWinProb: nil
        ),
        Game(
            id: UUID().uuidString,
            date: Date(),
            awayTeam: "Toronto Maple Leafs",
            homeTeam: "Buffalo Sabres",
            awayAbbrev: "TOR",
            homeAbbrev: "BUF",
            startTimeText: "7:30 PM",
            venue: "KeyBank Center",
            awayLogoURL: nil,
            homeLogoURL: nil,
            homeWinProb: nil,
            awayWinProb: nil
        ),
        Game(
            id: UUID().uuidString,
            date: Date().addingTimeInterval(60 * 60 * 3),
            awayTeam: "Colorado Avalanche",
            homeTeam: "Vegas Golden Knights",
            awayAbbrev: "COL",
            homeAbbrev: "VGK",
            startTimeText: "10:00 PM",
            venue: "T-Mobile Arena",
            awayLogoURL: nil,
            homeLogoURL: nil,
            homeWinProb: nil,
            awayWinProb: nil
        )
    ]

    static let teams: [Team] = [
        Team(
            id: UUID().uuidString,
            name: "Buffalo Sabres",
            abbrev: "BUF",
            city: "Buffalo",
            logoURL: nil,
            conference: "",
            division: "",
            rating: nil,
            playoffOdds: nil
        ),
        Team(
            id: UUID().uuidString,
            name: "New York Rangers",
            abbrev: "NYR",
            city: "New York",
            logoURL: nil,
            conference: "",
            division: "",
            rating: nil,
            playoffOdds: nil
        ),
        Team(
            id: UUID().uuidString,
            name: "New Jersey Devils",
            abbrev: "NJD",
            city: "New Jersey",
            logoURL: nil,
            conference: "",
            division: "",
            rating: nil,
            playoffOdds: nil
        ),
        Team(
            id: UUID().uuidString,
            name: "Toronto Maple Leafs",
            abbrev: "TOR",
            city: "Toronto",
            logoURL: nil,
            conference: "",
            division: "",
            rating: nil,
            playoffOdds: nil
        ),
        Team(
            id: UUID().uuidString,
            name: "Vegas Golden Knights",
            abbrev: "VGK",
            city: "Las Vegas",
            logoURL: nil,
            conference: "",
            division: "",
            rating: nil,
            playoffOdds: nil
        ),
        Team(
            id: UUID().uuidString,
            name: "Colorado Avalanche",
            abbrev: "COL",
            city: "Denver",
            logoURL: nil,
            conference: "",
            division: "",
            rating: nil,
            playoffOdds: nil
        )
    ]
}
