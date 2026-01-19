import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()
    let client: SupabaseClient

    // MARK: - Simple in-memory cache
    private var cachedTeams: [TeamDTO]?
    private var cachedTeamsById: [Int: TeamDTO]?

    private init() {
        let rawUrl = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String) ?? ""
        let rawKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String) ?? ""

        let urlString = rawUrl
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        let anonKey = rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL is not a valid URL: \(urlString)")
        }

        guard !anonKey.isEmpty else {
            fatalError("Missing SUPABASE_ANON_KEY")
        }

        // NOTE:
        // Your supabase-swift version does NOT support `localStorage`
        // so we keep auth options minimal.
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey
        )
    }

    // MARK: - Teams

    func fetchTeams(forceRefresh: Bool = false) async throws -> [TeamDTO] {
        if !forceRefresh, let cachedTeams {
            return cachedTeams
        }

        let dtos: [TeamDTO] = try await client
            .from("teams")
            .select()
            .order("team_id", ascending: true)
            .execute()
            .value

        cachedTeams = dtos
        cachedTeamsById = Dictionary(
            uniqueKeysWithValues: dtos.map { ($0.team_id, $0) }
        )

        return dtos
    }

    func getCachedTeamsById() -> [Int: TeamDTO]? {
        cachedTeamsById
    }

    // MARK: - Games

    func fetchGames(limit: Int = 200) async throws -> [GameDTO] {
        try await client
            .from("games")
            .select()
            .order("game_date", ascending: true)
            .order("start_time_utc", ascending: true)
            .limit(limit)
            .execute()
            .value
    }
}
