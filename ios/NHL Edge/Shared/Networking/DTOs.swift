import Foundation

struct TeamDTO: Decodable, Hashable {
    let team_id: Int
    let abbrev: String
    let name: String
    let city: String?
    let logo_url: String?
    let updated_at: String?
}


struct GameDTO: Decodable, Hashable {
    let game_id: Int
    let season: Int
    let game_type: String
    let game_date: String          // date comes back as "YYYY-MM-DD"
    let start_time_utc: String?    // timestamptz as ISO string
    let home_team_id: Int
    let away_team_id: Int
    let status: String?
    let venue: String?
    let last_ingested_at: String?
}

