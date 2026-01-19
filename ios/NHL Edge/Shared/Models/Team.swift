import Foundation

/// UI model for NHL teams used throughout the app.
///
/// Backed by Supabase `teams` table:
/// team_id (int4), abbrev (text), name (text), city (text),
/// logo_url (text), updated_at (timestamptz)
struct Team: Identifiable, Hashable {
    let id: String

    let name: String
    let abbrev: String
    let city: String

    /// Remote SVG logo URL (rendered via SVGKit)
    let logoURL: String?

    // Not yet in DB; placeholders for future modeling
    let conference: String
    let division: String
    let rating: Double?
    let playoffOdds: Double?
}   // ← THIS was missing or misplaced before

extension Team {
    /// Maps a Supabase TeamDTO to the UI Team model
    init(dto: TeamDTO) {
        self.id = String(dto.team_id)
        self.name = dto.name
        self.abbrev = dto.abbrev
        self.city = dto.city ?? ""
        self.logoURL = dto.logo_url

        // Not yet available in Supabase schema
        self.conference = ""
        self.division = ""
        self.rating = nil
        self.playoffOdds = nil
    }
}
