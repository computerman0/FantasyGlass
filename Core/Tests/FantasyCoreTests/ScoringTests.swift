import Foundation
import Testing
@testable import FantasyCore

private func decimal(_ text: String) -> Decimal { Decimal(string: text)! }

@Test(arguments: [("0", "21.6"), ("0.5", "25.1"), ("1", "28.6")])
func receptionFormats(ppr: String, expected: String) {
    let stats: [String: Decimal] = ["24":80,"25":1,"42":76,"53":7]
    let result = ScoringEngine.calculate(stats: stats, position: "2", rules: .standard(ppr: decimal(ppr)))
    #expect(result.total == decimal(expected))
}

@Test func allenBreakdown() {
    let result = ScoringEngine.calculate(stats: ["3":275,"4":3,"24":45], position: "0", rules: .standard())
    #expect(result.total == decimal("27.5"))
    #expect(result.contributions.map(\.points) == [11,12,decimal("4.5")])
}

@Test func customBonusNegativeAndFractions() {
    let config = ScoringConfiguration(name: "Custom", rules: [
        .init(stat:"3",label:"Yards",multiplier:decimal("0.033333")),
        .init(stat:"3",label:"300 yard bonus",multiplier:3,mode:.threshold,lower:300),
        .init(stat:"20",label:"Interceptions",multiplier:-3),
        .init(stat:"24",label:"Whole tens",multiplier:1,mode:.perWhole,lower:10)
    ])
    let result = ScoringEngine.calculate(stats:["3":301,"20":6,"24":-19], position:"0", rules:config)
    #expect(result.total == decimal("-5.966767"))
    #expect(result.issues.isEmpty)
}

@Test func kickerAndDefense() {
    let rules = ScoringConfiguration.standard()
    #expect(ScoringEngine.calculate(stats:["74":2,"77":1,"80":1,"86":3,"88":1],position:"17",rules:rules).total == 19)
    #expect(ScoringEngine.calculate(stats:["99":3,"95":2,"96":1,"105":1,"89":1],position:"16",rules:rules).total == 25)
    let custom = ScoringConfiguration(name:"Yards allowed",rules:[.init(stat:"127",label:"Under 100",multiplier:5,mode:.range,lower:0,upper:99)])
    #expect(ScoringEngine.calculate(stats:["127":80],position:"16",rules:custom).total == 5)
}

@Test func correctionsReplaceRatherThanAccumulate() {
    let rules = ScoringConfiguration.standard()
    let before = ScoringEngine.calculate(stats:["24":101,"72":1],position:"2",rules:rules)
    let after = ScoringEngine.calculate(stats:["24":99,"72":2],position:"2",rules:rules)
    #expect(before.total == decimal("8.1"))
    #expect(after.total == decimal("5.9"))
    #expect(after.total - before.total == decimal("-2.2"))
}

@Test func onePlayerDifferentLeaguesAndPositionRules() {
    let stats: [String:Decimal] = ["53":5,"42":61]
    #expect(ScoringEngine.calculate(stats:stats,position:"4",rules:.standard()).total == decimal("6.1"))
    #expect(ScoringEngine.calculate(stats:stats,position:"4",rules:.standard(ppr:1)).total == decimal("11.1"))
    let custom = ScoringConfiguration(name:"TE premium",rules:[.init(stat:"53",label:"Catches",multiplier:1,positionMultipliers:["6":decimal("1.5")])])
    #expect(ScoringEngine.calculate(stats:stats,position:"6",rules:custom).total == decimal("7.5"))
    #expect(ScoringEngine.calculate(stats:stats,position:"4",rules:custom).total == 5)
}

@Test func decimalRoundTripNeverSilentlyRounds() throws {
    let json = Data(#"{"points":0.123456789123456789}"#.utf8)
    let value = try JSONDecoder().decode(JSONValue.self,from:json)
    #expect(value["points"].decimal?.exact == "0.123456789123456789")
    #expect(try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(value)) == value)
    #expect(Decimal.parse("4 cats") == nil)
    #expect(Decimal.parse("0.00001") == decimal("0.00001"))
    #expect(Decimal.parse("+001.2300") == decimal("1.23"))
    #expect(Decimal.parse("-0.000") == 0)
    #expect(Decimal.parse("0.12345678901234567890123456789012345678901234") == nil)
    #expect(Decimal.parse("99999999999999999999999999999999999999999") == nil)
}

@Test func malformedRuleIsExplicit() {
    let rules = ScoringConfiguration(name:"Bad",rules:[.init(stat:"3",label:"Invalid bucket",multiplier:1,mode:.perWhole,lower:0)])
    #expect(!ScoringEngine.calculate(stats:["3":50],position:"0",rules:rules).issues.isEmpty)
}

@Test func decimalCapacityIsReportedInsteadOfClaimingAccuracy() throws {
    let huge = decimal("10000000000000000000000000000000000000")
    let rules = ScoringConfiguration(name:"Capacity test",rules:[.init(stat:"3",label:"Yards",multiplier:1)])
    var league = try ESPNProvider.decode(fixture("espn-league"),expectedLeagueID:"123",season:2026)
    var first = try #require(league.teams.first?.roster.first)
    first.weeks = [.init(week:7,stats:["3":huge])]
    var second = first; second.id = "another"; second.weeks = [.init(week:7,stats:["3":decimal("0.000000001")])]
    league.teams[0].roster = [first,second]
    let summary = Scores.team(league.teams[0],league:league,rules:rules,games:[])
    #expect(summary.local == nil)
    #expect(summary.warnings.contains { $0.contains("capacity") })
}

@Test func sharedBackendScoringContract() throws {
    struct Example: Decodable {
        var name: String; var stats: [String:Decimal]; var position: String; var rules: [ScoringRule]; var expected: String
    }
    let cases = try JSONDecoder().decode([Example].self,from:fixture("scoring-contract"))
    for example in cases {
        let result = ScoringEngine.calculate(stats:example.stats,position:example.position,rules:.init(name:example.name,rules:example.rules))
        #expect(result.issues.isEmpty)
        #expect(result.total.exact == example.expected)
    }
}
