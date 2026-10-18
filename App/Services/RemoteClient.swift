import Foundation
import FantasyCore

struct RemoteRule: Codable {
    var id: String; var stat: String; var label: String; var multiplier: String; var mode: String
    var lower: String?; var upper: String?; var positionMultipliers: [String:String]
    init(_ rule: ScoringRule) {
        id = rule.id; stat = rule.stat; label = rule.label; multiplier = rule.multiplier.exact; mode = rule.mode.rawValue
        lower = rule.lower?.exact; upper = rule.upper?.exact; positionMultipliers = rule.positionMultipliers.mapValues(\.exact)
    }
}
struct RemoteSubscription: Codable {
    var id: String
    var connectionID: String
    var leagueID: String
    var season: Int
    var teamID: Int
    var matchupID: String?
    var activityToken: String?
    var activityStartedAt: Double?
    var deviceToken: String?
    var s2: String?
    var swid: String?
    var rules: [RemoteRule]?
    var ruleIssues: [String]
    var enabledAlerts: [String]
    var thresholds: [String:String]
    var sportsDataKey: String?
    var playerMappings: [String:String]
    var accurateFeedConfirmed: Bool
}

struct RemoteClient: Sendable {
    let client = HTTPClient()
    func request(baseURL: String, token: String, path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let base = URL(string:baseURL), base.scheme == "https", let host = base.host, !host.isEmpty,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              token.count >= 32, !token.contains(where: \.isNewline) else {
            throw ProviderError.invalidInput("Use an HTTPS backend URL and its owner token (at least 32 characters).")
        }
        var request = URLRequest(url:base.appending(path:path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        return try await client.data(request)
    }
    func save(_ subscription: RemoteSubscription, baseURL: String, token: String) async throws {
        _ = try await request(baseURL:baseURL,token:token,path:"v1/subscriptions/\(subscription.id)",method:"PUT",body:JSONEncoder().encode(subscription))
    }
    func remove(id: String, baseURL: String, token: String) async throws {
        _ = try await request(baseURL:baseURL,token:token,path:"v1/subscriptions/\(id)",method:"DELETE")
    }
}
