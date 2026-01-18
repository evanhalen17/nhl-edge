import Foundation

struct Team: Identifiable, Hashable {
    let id: String
    let name: String
    let abbrev: String
    let city: String
    let conference: String
    let division: String

    let rating: Double?
    let playoffOdds: Double?
}


extension Team {
    init(dto: TeamDTO) {
        self.id = String(dto.team_id)
        self.name = dto.name
        self.abbrev = dto.abbrev
        self.city = dto.city ?? ""
        self.conference = ""   // not in DB yet
        self.division = ""     // not in DB yet
        self.rating = nil      // not in DB yet
        self.playoffOdds = nil // not in DB yet
    }
}

