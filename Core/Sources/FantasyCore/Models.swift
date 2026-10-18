import Foundation

public struct LeagueConnection: Codable, Identifiable, Hashable, Sendable {
    public var provider = "espn"
    public var leagueID: String
    public var season: Int
    public var teamID: Int
    public var accountID: String
    public var id: String { "\(provider):\(season):\(leagueID):\(teamID)" }
    public init(leagueID: String, season: Int, teamID: Int, accountID: String = "default") {
        self.leagueID = leagueID; self.season = season; self.teamID = teamID; self.accountID = accountID
    }
}

public enum GamePhase: String, Codable, CaseIterable, Sendable { case scheduled, live, halftime, final, postponed, canceled, unknown }

public struct NFLGame: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var home: String
    public var away: String
    public var start: Date
    public var phase: GamePhase
    public var detail: String
    public var period: Int
    public var clock: String
    public var fetchedAt: Date
    public var active: Bool { phase == .live || phase == .halftime }
    public var remaining: Bool { phase == .scheduled || phase == .postponed }
    public func opponent(of team: String) -> String { team == home ? away : home }
    public init(id: String, home: String, away: String, start: Date, phase: GamePhase, detail: String, period: Int = 0, clock: String = "", fetchedAt: Date = .now) {
        self.id = id; self.home = home; self.away = away; self.start = start; self.phase = phase; self.detail = detail; self.period = period; self.clock = clock; self.fetchedAt = fetchedAt
    }
}

public struct PlayerWeek: Codable, Equatable, Sendable {
    public var week: Int
    public var stats: [String: Decimal]?
    public var projectionStats: [String: Decimal]?
    public var official: Decimal?
    public var projected: Decimal?
    public init(week: Int, stats: [String: Decimal]? = nil, projectionStats: [String: Decimal]? = nil, official: Decimal? = nil, projected: Decimal? = nil) {
        self.week = week; self.stats = stats; self.projectionStats = projectionStats; self.official = official; self.projected = projected
    }
}

public struct RosterPlayer: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var nflTeam: String
    public var position: String
    /// ESPN position scoring overrides use lineup position IDs, not defaultPositionId.
    public var scoringPosition: String
    public var slot: Int
    public var jersey: String?
    public var photoURL: URL?
    public var injury: String
    public var weeks: [PlayerWeek]
    public var source: String
    public var fetchedAt: Date
    public var starter: Bool { ![20, 21, 24, 25].contains(slot) }
    public var injured: Bool { !["ACTIVE", "NORMAL", "HEALTHY", "UNKNOWN", ""].contains(injury.uppercased()) }
    public func week(_ n: Int) -> PlayerWeek? { weeks.first { $0.week == n } }
    public init(id: String, name: String, nflTeam: String, position: String, scoringPosition: String, slot: Int, jersey: String? = nil, photoURL: URL? = nil, injury: String = "ACTIVE", weeks: [PlayerWeek] = [], source: String = "ESPN unofficial", fetchedAt: Date = .now) {
        self.id = id; self.name = name; self.nflTeam = nflTeam; self.position = position; self.scoringPosition = scoringPosition; self.slot = slot; self.jersey = jersey; self.photoURL = photoURL; self.injury = injury; self.weeks = weeks; self.source = source; self.fetchedAt = fetchedAt
    }
}

public struct FantasyTeam: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var wins: Int
    public var losses: Int
    public var ties: Int
    public var rank: Int?
    public var owners: [String]
    public var roster: [RosterPlayer]
    public var record: String { "\(wins)–\(losses)" + (ties == 0 ? "" : "–\(ties)") }
    public init(id: Int, name: String, wins: Int = 0, losses: Int = 0, ties: Int = 0, rank: Int? = nil, owners: [String] = [], roster: [RosterPlayer] = []) {
        self.id = id; self.name = name; self.wins = wins; self.losses = losses; self.ties = ties; self.rank = rank; self.owners = owners; self.roster = roster
    }
}

public struct FantasyMatchup: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var period: Int
    public var homeID: Int
    public var awayID: Int?
    public var homeOfficial: Decimal?
    public var awayOfficial: Decimal?
    public var homeAdjustment: Decimal
    public var awayAdjustment: Decimal
    public var winner: String
    public var weeks: [Int]
    public func contains(_ team: Int) -> Bool { homeID == team || awayID == team }
    public init(id: String, period: Int, homeID: Int, awayID: Int?, homeOfficial: Decimal? = nil, awayOfficial: Decimal? = nil, homeAdjustment: Decimal = 0, awayAdjustment: Decimal = 0, winner: String = "UNDECIDED", weeks: [Int] = []) {
        self.id = id; self.period = period; self.homeID = homeID; self.awayID = awayID; self.homeOfficial = homeOfficial; self.awayOfficial = awayOfficial; self.homeAdjustment = homeAdjustment; self.awayAdjustment = awayAdjustment; self.winner = winner; self.weeks = weeks
    }
}

public struct LeagueSnapshot: Codable, Equatable, Sendable {
    public var leagueID: String
    public var season: Int
    public var name: String
    public var week: Int
    public var matchupPeriod: Int
    public var teams: [FantasyTeam]
    public var schedule: [FantasyMatchup]
    public var importedRules: ScoringConfiguration
    public var fetchedAt: Date
    public var warnings: [String]
    public func team(_ id: Int) -> FantasyTeam? { teams.first { $0.id == id } }
    public func matchup(for teamID: Int) -> FantasyMatchup? { schedule.first { $0.period == matchupPeriod && $0.contains(teamID) } }
    public init(leagueID: String, season: Int, name: String, week: Int, matchupPeriod: Int, teams: [FantasyTeam], schedule: [FantasyMatchup], importedRules: ScoringConfiguration, fetchedAt: Date = .now, warnings: [String] = []) {
        self.leagueID = leagueID; self.season = season; self.name = name; self.week = week; self.matchupPeriod = matchupPeriod; self.teams = teams; self.schedule = schedule; self.importedRules = importedRules; self.fetchedAt = fetchedAt; self.warnings = warnings
    }
}

public struct ScoreSummary: Sendable {
    public var local: Decimal?
    public var official: Decimal?
    public var projected: Decimal?
    public var playing: Int
    public var remaining: Int
    public var total: Int
    public var warnings: [String]
    public var difference: Decimal? { if let local, let official { local - official } else { nil } }
}

public enum Scores {
    public static func team(_ team: FantasyTeam, league: LeagueSnapshot, rules: ScoringConfiguration, games: [NFLGame]) -> ScoreSummary {
        let starters = team.roster.filter(\.starter)
        let matchup = league.matchup(for: team.id)
        var total: Decimal = 0, projected: Decimal = 0
        var complete = !starters.isEmpty && rules.issues.isEmpty, hasProjection = !starters.isEmpty
        var warnings = rules.issues
        for player in starters {
            let game = games.first { $0.home == player.nflTeam || $0.away == player.nflTeam }
            if let stats = player.week(league.week)?.stats {
                let result = ScoringEngine.calculate(stats: stats, position: player.scoringPosition, rules: rules)
                if !addExactly(result.total,to:&total) {
                    complete = false; warnings.append("Team total exceeds decimal capacity; official score retained")
                }
                warnings += result.issues; complete = complete && result.issues.isEmpty
            } else if game?.phase != .scheduled { complete = false }
            if let stats = player.week(league.week)?.projectionStats {
                let result = ScoringEngine.calculate(stats: stats, position: player.scoringPosition, rules: rules)
                if !addExactly(result.total,to:&projected) { hasProjection = false }
                hasProjection = hasProjection && result.issues.isEmpty
            } else { hasProjection = false }
        }
        // A current-week roster cannot reconstruct prior-week playoff lineups. Never pretend it can.
        if let matchup, matchup.weeks.count > 1 {
            complete = false; hasProjection = false
            warnings.append("Multi-week matchup: official aggregate shown; local player scores are for this week.")
        }
        let home = matchup?.homeID == team.id
        if !addExactly((home ? matchup?.homeAdjustment : matchup?.awayAdjustment) ?? 0,to:&total) {
            complete = false; warnings.append("Matchup adjustment exceeds decimal capacity; official score retained")
        }
        return ScoreSummary(local: complete ? total : nil, official: home ? matchup?.homeOfficial : matchup?.awayOfficial,
            projected: hasProjection ? projected : nil,
            playing: starters.filter { p in games.contains { ($0.home == p.nflTeam || $0.away == p.nflTeam) && $0.active } }.count,
            remaining: starters.filter { p in games.contains { ($0.home == p.nflTeam || $0.away == p.nflTeam) && $0.remaining } }.count,
            total: starters.count, warnings: Array(Set(warnings)).sorted())
    }
    private static func addExactly(_ value: Decimal, to total: inout Decimal) -> Bool {
        var lhs = total, rhs = value
        return NSDecimalAdd(&total,&lhs,&rhs,.plain) == .noError && !total.isNaN
    }
}
