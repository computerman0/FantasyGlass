import Foundation
import ActivityKit

struct MatchupActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var myScore: String
        var opponentScore: String
        var myProjection: String?
        var opponentProjection: String?
        var myRemaining: Int
        var opponentRemaining: Int
        var myPlaying: Int
        var opponentPlaying: Int
        var progress: Double
        var leader: Int
        var status: String
        var updatedAt: Double
        var scoreSource: String
    }
    var connectionID: String
    var matchupID: String
    var myTeam: String
    var opponentTeam: String
    var leagueName: String
}

enum MatchupLink {
    static func url(connectionID: String, matchupID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "fantasyglass"; components.host = "matchup"
        components.queryItems = [.init(name:"connection",value:connectionID),.init(name:"matchup",value:matchupID)]
        return components.url
    }
    static func parse(_ url: URL) -> (connection: String, matchup: String)? {
        guard url.scheme == "fantasyglass", url.host == "matchup", let components = URLComponents(url:url,resolvingAgainstBaseURL:false),
              let connection = components.queryItems?.first(where: { $0.name == "connection" })?.value,
              let matchup = components.queryItems?.first(where: { $0.name == "matchup" })?.value else { return nil }
        return (connection,matchup)
    }
}
