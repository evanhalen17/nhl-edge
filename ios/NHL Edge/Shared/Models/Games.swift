import Foundation

/// UI model used by SwiftUI lists/detail screens.
///
/// This model is *not* a 1:1 match to the `games` table schema:
/// - Supabase `games` has `home_team_id` / `away_team_id` (ints), not names/abbrevs.
/// - We resolve names/abbrevs by joining against `teams` (client-side).
struct Game: Identifiable, Hashable {
    let id: String

    let date: Date
    let awayTeam: String
    let homeTeam: String
    let awayAbbrev: String
    let homeAbbrev: String
    let startTimeText: String
    let venue: String?

    // Not present in your current `games` table schema; placeholders for projections later
    let homeWinProb: Double?
    let awayWinProb: Double?
}

extension Game {
    // MARK: - Date parsing helpers

    /// Parses `game_date` from Supabase `date` column (typically "YYYY-MM-DD").
    static func parseGameDate(_ s: String) -> Date {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s) ?? Date()
    }

    /// Parses Supabase `timestamptz` ISO strings (with or without fractional seconds).
    static func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    // MARK: - Mapping from Supabase DTOs

    /// Builds a `Game` using a `GameDTO` row plus a team lookup dictionary.
    ///
    /// Expected DTO fields (per your Supabase schema):
    /// `GameDTO`: game_id(Int), game_date(String), start_time_utc(String?),
    ///           home_team_id(Int), away_team_id(Int), venue(String?)
    /// `TeamDTO`: team_id(Int), name(String), abbrev(String)
    init(dto: GameDTO, teamById: [Int: TeamDTO]) {
        let away = teamById[dto.away_team_id]
        let home = teamById[dto.home_team_id]

        let resolvedDate: Date = {
            if let s = dto.start_time_utc, let d = Game.parseISO(s) {
                return d
            }
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
        self.homeWinProb = nil
        self.awayWinProb = nil
    }
}
