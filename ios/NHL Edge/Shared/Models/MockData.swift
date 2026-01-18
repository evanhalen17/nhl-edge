import Foundation

enum MockData {
    static let calendar = Calendar.current

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
            homeWinProb: 0.54,
            awayWinProb: 0.46
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
            homeWinProb: 0.48,
            awayWinProb: 0.52
        ),
        Game(
            id: UUID().uuidString,
            date: Date(),
            awayTeam: "Colorado Avalanche",
            homeTeam: "Vegas Golden Knights",
            awayAbbrev: "COL",
            homeAbbrev: "VGK",
            startTimeText: "10:00 PM",
            venue: "T-Mobile Arena",
            homeWinProb: nil,
            awayWinProb: nil
        )
    ]
}

extension MockData {
    static let teams: [Team] = [
        Team(id: UUID().uuidString, name: "Buffalo Sabres", abbrev: "BUF", city: "Buffalo", conference: "Eastern", division: "Atlantic", rating: 0.2, playoffOdds: 0.18),
        Team(id: UUID().uuidString, name: "New York Rangers", abbrev: "NYR", city: "New York", conference: "Eastern", division: "Metropolitan", rating: 1.1, playoffOdds: 0.72),
        Team(id: UUID().uuidString, name: "New Jersey Devils", abbrev: "NJD", city: "New Jersey", conference: "Eastern", division: "Metropolitan", rating: 0.9, playoffOdds: 0.64),
        Team(id: UUID().uuidString, name: "Toronto Maple Leafs", abbrev: "TOR", city: "Toronto", conference: "Eastern", division: "Atlantic", rating: 0.8, playoffOdds: 0.61),
        Team(id: UUID().uuidString, name: "Vegas Golden Knights", abbrev: "VGK", city: "Las Vegas", conference: "Western", division: "Pacific", rating: 1.0, playoffOdds: 0.69),
        Team(id: UUID().uuidString, name: "Colorado Avalanche", abbrev: "COL", city: "Denver", conference: "Western", division: "Central", rating: 1.2, playoffOdds: 0.75)
    ]
}
