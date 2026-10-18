import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import FantasyCore

func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension:"json",subdirectory:"Fixtures")))
}
actor MockTransport: HTTPTransport {
    var replies: [HTTPReply]
    var requests: [URLRequest] = []
    init(_ replies: [HTTPReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPReply {
        requests.append(request)
        return replies.isEmpty ? HTTPReply(data:Data(),status:500) : replies.removeFirst()
    }
}

@Test func leagueImportAndLocalTotals() throws {
    let snapshot = try ESPNProvider.decode(fixture("espn-league"),expectedLeagueID:"123",season:2026)
    #expect(snapshot.name == "Fixture League (not live)")
    #expect(snapshot.team(1)?.record == "4–2")
    let result = Scores.team(try #require(snapshot.team(1)),league:snapshot,rules:snapshot.importedRules,games:[])
    #expect(result.local == Decimal(string:"27.5"))
    #expect(result.difference == 0)
    var override = snapshot.importedRules
    override.rules[0].multiplier = Decimal(string:"0.05")!
    #expect(Scores.team(try #require(snapshot.team(1)),league:snapshot,rules:override,games:[]).difference == Decimal(string:"2.75"))
    #expect(snapshot.importedRules.rules[0].multiplier == Decimal(string:"0.04"))
    #expect(try JSONDecoder().decode(LeagueSnapshot.self,from:JSONEncoder().encode(snapshot)) == snapshot)
}

@Test func missingRawStatsDoNotBecomeZero() throws {
    var league = try ESPNProvider.decode(fixture("espn-league"),expectedLeagueID:"123",season:2026)
    league.teams[0].roster[0].weeks = []
    #expect(Scores.team(league.teams[0],league:league,rules:league.importedRules,games:[]).local == nil)
    league.schedule[0].weeks = [7,8]
    #expect(Scores.team(league.teams[1],league:league,rules:league.importedRules,games:[]).local == nil)
}

@Test func authenticatedRequestAndErrors() async throws {
    let transport = MockTransport([.init(data:try fixture("espn-league"))])
    let provider = ESPNProvider(client:HTTPClient(transport:transport))
    _ = try await provider.load(leagueID:"123",season:2026,credentials:ESPNCredentials(s2:"fixture-token",swid:"{fixture-user}"),week:7)
    let request = try #require(await transport.requests.first)
    #expect(request.value(forHTTPHeaderField:"Cookie") == "espn_s2=fixture-token; SWID={fixture-user}")
    #expect(request.url?.query?.contains("scoringPeriodId=7") == true)
    for status in [401,403,404] {
        let failing = ESPNProvider(client:HTTPClient(transport:MockTransport([.init(data:Data(),status:status)])))
        await #expect(throws: ProviderError.self) { try await failing.load(leagueID:"123",season:2026,credentials:nil) }
    }
    #expect(throws: ProviderError.self) { try ESPNCredentials(s2:"x\nInjected",swid:"x") }
}

@Test func rateLimitIsSharedAndHonorsRetryAfter() async throws {
    let transport = MockTransport([.init(data:Data(),status:429,retryAfter:300),.init(data:Data())])
    let client = HTTPClient(transport:transport)
    let request = URLRequest(url:URL(string:"https://example.com/stats")!)
    await #expect(throws:ProviderError.rateLimited(300)) { try await client.data(request) }
    await #expect(throws:ProviderError.self) { try await client.data(request) }
    #expect(await transport.requests.count == 1)
}

@Test func serverRetryRecovers() async throws {
    let transport = MockTransport([.init(data:Data(),status:503),.init(data:Data("ok".utf8))])
    let result = try await HTTPClient(transport:transport).data(URLRequest(url:URL(string:"https://example.com")!))
    #expect(result == Data("ok".utf8))
    #expect(await transport.requests.count == 2)
}

@Test func scoreboardAndRefreshPolicy() throws {
    let games = try ESPNScoreboardProvider.decode(fixture("espn-scoreboard"))
    #expect(!games.isEmpty)
    #expect(games.contains { $0.phase == .final })
    #expect(RefreshPolicy.interval(games:games) == 900)
    var game = try #require(games.first); game.phase = .live
    #expect(RefreshPolicy.interval(games:[game]) == 60)
    #expect(RefreshPolicy.stale(fetchedAt:.now.addingTimeInterval(-121),active:true))
}

@Test func optionalProviderRequiresExplicitCoverage() throws {
    let players = try SportsDataIOProvider.decode(fixture("sportsdata-players"))
    #expect(players.first?.stats["3"] == 275)
    let league = try ESPNProvider.decode(fixture("espn-league"),expectedLeagueID:"123",season:2026)
    let player = try #require(league.teams.first?.roster.first)
    #expect(SportsDataIOProvider.missingCategories(for:player,rules:league.importedRules,external:players[0]).isEmpty)
    #expect(!SportsDataIOProvider.missingCategories(for:player,rules:.standard(),external:players[0]).isEmpty)
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["FANTASYGLASS_LIVE_SMOKE"] == "1"))
func publicESPNLiveSmoke() async throws {
    let league = try await ESPNProvider().load(leagueID:"48153503",season:2019,credentials:nil)
    #expect(league.teams.count == 14)
    #expect(!league.importedRules.rules.isEmpty)
    #expect(!league.schedule.isEmpty)
    #expect(league.teams.contains { !$0.roster.isEmpty })
    let games = try await ESPNScoreboardProvider().games(season:2025,week:6)
    #expect(games.count == 15)
    #expect(games.allSatisfy { $0.phase == .final })
}
