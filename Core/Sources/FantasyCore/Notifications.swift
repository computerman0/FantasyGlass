import Foundation

public enum AlertKind: String, Codable, CaseIterable, Sendable {
    case touchdown, leadChange, closeFinalGame, injuredOut, halftime, final, correction, threshold
    public var title: String {
        switch self {
        case .touchdown: "Player touchdown"
        case .leadChange: "Matchup leader changes"
        case .closeFinalGame: "Close matchup in the last NFL game"
        case .injuredOut: "Player declared out"
        case .halftime: "NFL halftime"
        case .final: "NFL final"
        case .correction: "Correction changes the result"
        case .threshold: "Player point threshold"
        }
    }
}
public struct AlertPreferences: Codable, Sendable, Equatable {
    public var enabled: Set<AlertKind>
    public var thresholds: [String: Decimal]
    public init(enabled: Set<AlertKind> = [], thresholds: [String: Decimal] = [:]) { self.enabled = enabled; self.thresholds = thresholds }
}
public struct ObservedPlayer: Codable, Equatable, Sendable {
    public var name: String
    public var touchdowns: Decimal
    public var points: Decimal?
    public var injury: String
}
public struct EventFrame: Codable, Sendable, Equatable {
    public var scope: String
    public var players: [String: ObservedPlayer]
    public var games: [String: GamePhase]
    public var ownScore: Decimal?
    public var opponentScore: Decimal?
    public var lastGameLive: Bool
    public var finished: Bool
    public var leader: Int? {
        guard let ownScore, let opponentScore else { return nil }
        return ownScore == opponentScore ? 0 : ownScore > opponentScore ? 1 : -1
    }
    public init(scope: String, players: [String: ObservedPlayer], games: [String: GamePhase], ownScore: Decimal?, opponentScore: Decimal?, lastGameLive: Bool, finished: Bool) {
        self.scope = scope; self.players = players; self.games = games; self.ownScore = ownScore; self.opponentScore = opponentScore; self.lastGameLive = lastGameLive; self.finished = finished
    }
    public static func make(connection: LeagueConnection, league: LeagueSnapshot, rules: ScoringConfiguration, games: [NFLGame]) -> EventFrame {
        let team = league.team(connection.teamID)
        let matchup = league.matchup(for: connection.teamID)
        let opponentID = matchup?.homeID == connection.teamID ? matchup?.awayID : matchup?.homeID
        let own = team.map { Scores.team($0, league: league, rules: rules, games: games) }
        let opposing = opponentID.flatMap(league.team).map { Scores.team($0, league: league, rules: rules, games: games) }
        var players: [String: ObservedPlayer] = [:]
        for player in team?.roster ?? [] {
            let raw = player.week(league.week)?.stats
            let score = raw.map { ScoringEngine.calculate(stats: $0, position: player.scoringPosition, rules: rules) }
            let touchdowns = ["4","25","43","63","101","102","103","104"].reduce(Decimal.zero) { $0 + (raw?[$1] ?? 0) }
            players[player.id] = .init(name: player.name, touchdowns: touchdowns, points: score?.issues.isEmpty == true ? score?.total : nil, injury: player.injury)
        }
        return .init(scope: "\(connection.id):\(league.week)", players: players, games: Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.phase) }),
            ownScore: own?.local ?? own?.official, opponentScore: opposing?.local ?? opposing?.official,
            lastGameLive: games.filter(\.active).count == 1 && !games.contains(where: \.remaining),
            finished: !games.isEmpty && games.allSatisfy { $0.phase == .final || $0.phase == .canceled })
    }
}
public struct FantasyAlert: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var kind: AlertKind
    public var title: String
    public var body: String
}
public enum EventDetector {
    public static func detect(previous: EventFrame?, current: EventFrame, preferences: AlertPreferences) -> [FantasyAlert] {
        guard let previous, previous.scope == current.scope else { return [] }
        var events: [FantasyAlert] = []
        func emit(_ kind: AlertKind, _ suffix: String, _ title: String, _ body: String) {
            guard preferences.enabled.contains(kind) else { return }
            events.append(.init(id: "\(current.scope):\(kind.rawValue):\(suffix)", kind: kind, title: title, body: body))
        }
        for (id, player) in current.players {
            guard let before = previous.players[id] else { continue }
            if player.touchdowns > before.touchdowns { emit(.touchdown, "\(id):\(player.touchdowns.exact)", "\(player.name) touchdown", "New touchdown reported by the statistics provider; corrections may follow.") }
            if player.injury.uppercased() == "OUT" && before.injury.uppercased() != "OUT" { emit(.injuredOut, id, "\(player.name) is out", "Review your fantasy lineup.") }
            if let threshold = preferences.thresholds[id], let score = player.points, let old = before.points, old < threshold && score >= threshold {
                emit(.threshold, "\(id):\(threshold.exact)", "\(player.name) reached \(threshold.exact)", "Now at \(score.exact) fantasy points in this league.")
            }
        }
        if let leader = current.leader, let before = previous.leader, leader != before {
            let scores = "\(current.ownScore?.exact ?? "—")–\(current.opponentScore?.exact ?? "—")"
            emit(previous.finished && current.finished ? .correction : .leadChange, "\(leader):\(scores)", previous.finished && current.finished ? "Stat correction changed the result" : "Matchup leader changed", scores)
        }
        if current.lastGameLive && !previous.lastGameLive, let mine = current.ownScore, let theirs = current.opponentScore, abs(mine - theirs) <= 10 {
            emit(.closeFinalGame, "last", "A close finish", "Your matchup is within 10 points as the final NFL game is underway.")
        }
        for (id, phase) in current.games where previous.games[id] != nil && previous.games[id] != phase {
            if phase == .halftime { emit(.halftime, id, "NFL halftime", "Game \(id) has reached halftime.") }
            if phase == .final { emit(.final, id, "NFL game final", "Game \(id) is final. Stat corrections remain possible.") }
        }
        return events
    }
}
