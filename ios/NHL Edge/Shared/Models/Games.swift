import Foundation

struct Game: Identifiable, Hashable {
    let id: String

    let date: Date
    let awayTeam: String
    let homeTeam: String
    let awayAbbrev: String
    let homeAbbrev: String
    let startTimeText: String
    let venue: String?

    // Logos (SVG URLs from teams table)
    let awayLogoURL: String?
    let homeLogoURL: String?

    // Not present in your current `games` table schema; placeholders for projections later
    let homeWinProb: Double?
    let awayWinProb: Double?
}

extension Game {
    static func parseGameDate(_ s: String) -> Date {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s) ?? Date()
    }

    static func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    init(dto: GameDTO, teamById: [Int: TeamDTO]) {
        let away = teamById[dto.away_team_id]
        let home = teamById[dto.home_team_id]

        let resolvedDate: Date = {
            if let s = dto.start_time_utc, let d = Game.parseISO(s) { return d }
            return Game.parseGameDate(dto.game_date)
        }()

        let startText: String = {
            if let s = dto.start_time_utc, let d = Game.parseISO(s) {
                return d.formatted(date: .omitted, time: .shortened)
            }
            return ""
        }()

        self.id = String(dto.game_id)
        self.date = resolvedDate
        self.awayTeam = away?.name ?? "Away"
        self.homeTeam = home?.name ?? "Home"
        self.awayAbbrev = away?.abbrev ?? "AWY"
        self.homeAbbrev = home?.abbrev ?? "HME"
        self.startTimeText = startText
        self.venue = dto.venue

        self.awayLogoURL = away?.logo_url
        self.homeLogoURL = home?.logo_url

        self.homeWinProb = nil
        self.awayWinProb = nil
    }
}
