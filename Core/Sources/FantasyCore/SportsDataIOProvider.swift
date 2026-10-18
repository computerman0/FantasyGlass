import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ExternalPlayerStats: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var team: String
    public var stats: [String: Decimal]
    public var fetchedAt: Date
}

public struct SportsDataIOProvider: Sendable {
    public let client: HTTPClient
    public init(client: HTTPClient = HTTPClient()) { self.client = client }
    /// A successful trial request does not establish that the statistics are accurate or unscrumbled.
    public func playerStats(season: Int, week: Int, apiKey: String) async throws -> [ExternalPlayerStats] {
        guard (2018...2100).contains(season), (1...18).contains(week), !apiKey.isEmpty,
              !apiKey.contains(where: \.isNewline) else { throw ProviderError.invalidInput("A valid API key, season and NFL regular-season week are required.") }
        let url = URL(string: "https://api.sportsdata.io/v3/nfl/stats/json/PlayerGameStatsByWeek/\(season)REG/\(week)")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        return try Self.decode(await client.data(request))
    }
    public static let fields: [String: String] = [
        "0":"PassingAttempts", "1":"PassingCompletions", "3":"PassingYards", "4":"PassingTouchdowns", "20":"PassingInterceptions", "19":"TwoPointConversionPasses",
        "23":"RushingAttempts", "24":"RushingYards", "25":"RushingTouchdowns", "26":"TwoPointConversionRuns",
        "41":"Receptions", "53":"Receptions", "42":"ReceivingYards", "43":"ReceivingTouchdowns", "44":"TwoPointConversionReceptions", "58":"ReceivingTargets",
        "68":"Fumbles", "72":"FumblesLost", "63":"FumbleReturnTouchdowns", "64":"PassingSacks",
        "74":"FieldGoalsMade50Plus", "77":"FieldGoalsMade40to49", "83":"FieldGoalsMade", "84":"FieldGoalsAttempted",
        "86":"ExtraPointsMade", "87":"ExtraPointsAttempted", "101":"KickReturnTouchdowns", "102":"PuntReturnTouchdowns",
        "95":"Interceptions", "96":"FumblesRecovered", "99":"Sacks", "106":"FumblesForced", "107":"AssistedTackles", "108":"SoloTackles", "113":"PassesDefended"
    ]
    public static func decode(_ data: Data, now: Date = .now) throws -> [ExternalPlayerStats] {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .array = root else { throw ProviderError.invalidResponse("SportsDataIO did not return a player array. Check the NFL statistics entitlement.") }
        return root.array.compactMap { row in
            guard let id = row["PlayerID"].textID, let name = row["Name"].string else { return nil }
            var stats: [String: Decimal] = [:]
            for (key, field) in fields { if let value = row[field].decimal { stats[key] = value } }
            if let a = row["FieldGoalsMade0to19"].decimal, let b = row["FieldGoalsMade20to29"].decimal, let c = row["FieldGoalsMade30to39"].decimal { stats["80"] = a + b + c }
            for (key, made, attempted) in [("85","FieldGoalsMade","FieldGoalsAttempted"),("88","ExtraPointsMade","ExtraPointsAttempted")] {
                if let m = row[made].decimal, let a = row[attempted].decimal { stats[key] = a - m }
            }
            return ExternalPlayerStats(id: id, name: name, team: row["Team"].string ?? "", stats: stats, fetchedAt: now)
        }
    }
    public static func missingCategories(for player: RosterPlayer, rules: ScoringConfiguration, external: ExternalPlayerStats) -> [String] {
        rules.rules.filter { ($0.positionMultipliers[player.scoringPosition] ?? $0.multiplier) != 0 && external.stats[$0.stat] == nil }.map(\.label)
    }
}
