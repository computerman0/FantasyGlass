import Foundation

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
