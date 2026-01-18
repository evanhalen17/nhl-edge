import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()
    let client: SupabaseClient

    private init() {
        let rawUrl = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String) ?? ""
        let rawKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String) ?? ""

        let urlString = rawUrl
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        let anonKey = rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        print("🔥 SUPABASE_URL:", urlString.isEmpty ? "EMPTY" : urlString)
        print("🔥 SUPABASE_ANON_KEY present:", !anonKey.isEmpty)

        guard let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL is not a valid URL: \(urlString)")
        }
        guard !anonKey.isEmpty else {
            fatalError("Missing SUPABASE_ANON_KEY")
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainLocalStorage(),
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    func fetchTeams() async throws -> [TeamDTO] {
        try await client
            .from("teams")
            .select()
            .execute()
            .value
    }

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
