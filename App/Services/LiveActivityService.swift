import Foundation
@preconcurrency import ActivityKit
import Observation
import FantasyCore

@Observable @MainActor final class LiveActivityService {
    var trackedConnection: String?
    var lastError: String?
    var onTokenChange: (@MainActor () async -> Void)?
    private var tokenObservers: [String:Task<Void,Never>] = [:]
    private var stateObservers: [String:Task<Void,Never>] = [:]
    private(set) var tokens: [String:String] = [:]
    private(set) var started: [String:Date] = [:]
    init() { restore() }
    var supportsActivities: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    func restore() {
        for activity in Activity<MatchupActivityAttributes>.activities {
            guard activity.activityState == .active || activity.activityState == .stale else { continue }
            trackedConnection = activity.attributes.connectionID
            observe(activity)
        }
    }
    func token(for connectionID: String) -> String? {
        guard let activity = Activity<MatchupActivityAttributes>.activities.first(where: { $0.attributes.connectionID == connectionID && ($0.activityState == .active || $0.activityState == .stale) }) else { return nil }
        return tokens[activity.id] ?? activity.pushToken.map { $0.map { String(format:"%02x",$0) }.joined() }
    }
    func startedAt(for connectionID: String) -> Date? {
        guard let activity = Activity<MatchupActivityAttributes>.activities.first(where: { $0.attributes.connectionID == connectionID }) else { return nil }
        // Restored activities without a persisted timestamp get a conservative expiry on the backend.
        return started[activity.id] ?? UserDefaults.standard.object(forKey:"activity.start.\(activity.id)") as? Date
    }
    func start(_ league: LeagueState, games: [NFLGame], remote: Bool) async throws {
        guard supportsActivities else { throw ProviderError.invalidInput("Enable Live Activities for FantasyGlass in iOS Settings. A compatible physical iPhone is required for Dynamic Island.") }
        guard let mine = league.team, let opponent = league.opponent, let matchup = league.matchup else { throw ProviderError.invalidInput("This team has no current head-to-head matchup to track.") }
        await end()
        let attributes = MatchupActivityAttributes(connectionID:league.id,matchupID:matchup.id,myTeam:String(mine.name.prefix(80)),opponentTeam:String(opponent.name.prefix(80)),leagueName:String(league.snapshot.name.prefix(80)))
        let state = content(league,games:games)
        let activity = try Activity.request(attributes:attributes,content:ActivityContent(state:state,staleDate:league.snapshot.fetchedAt.addingTimeInterval(120)),pushType:remote ? .token : nil)
        trackedConnection = league.id
        started[activity.id] = .now
        UserDefaults.standard.set(Date.now,forKey:"activity.start.\(activity.id)")
        observe(activity)
    }
    func update(_ league: LeagueState, games: [NFLGame]) async {
        for activity in Activity<MatchupActivityAttributes>.activities where activity.attributes.connectionID == league.id {
            guard league.matchup?.id == activity.attributes.matchupID else {
                await activity.end(nil,dismissalPolicy:.immediate); continue
            }
            await activity.update(ActivityContent(state:content(league,games:games),staleDate:league.snapshot.fetchedAt.addingTimeInterval(120)))
        }
    }
    func end() async {
        for activity in Activity<MatchupActivityAttributes>.activities {
            await activity.end(nil,dismissalPolicy:.immediate)
            tokenObservers.removeValue(forKey:activity.id)?.cancel()
            stateObservers.removeValue(forKey:activity.id)?.cancel()
            tokens.removeValue(forKey:activity.id); started.removeValue(forKey:activity.id)
            UserDefaults.standard.removeObject(forKey:"activity.start.\(activity.id)")
        }
        trackedConnection = nil
    }
    private func observe(_ activity: Activity<MatchupActivityAttributes>) {
        guard tokenObservers[activity.id] == nil else { return }
        // Both observers stay on MainActor with the ActivityKit reference. Only
        // Codable/Sendable content is handed to the independent network service.
        tokenObservers[activity.id] = Task { @MainActor [weak self] in
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                self?.tokens[activity.id] = token.map { String(format:"%02x",$0) }.joined()
                await self?.onTokenChange?()
            }
        }
        stateObservers[activity.id] = Task { @MainActor [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { break }
                if state == .ended || state == .dismissed {
                    self?.tokenObservers.removeValue(forKey:activity.id)?.cancel()
                    self?.stateObservers.removeValue(forKey:activity.id)
                    self?.tokens.removeValue(forKey:activity.id)
                    self?.started.removeValue(forKey:activity.id)
                    UserDefaults.standard.removeObject(forKey:"activity.start.\(activity.id)")
                    if self?.trackedConnection == activity.attributes.connectionID { self?.trackedConnection = nil }
                    await self?.onTokenChange?()
                    break
                }
            }
        }
    }
    private func content(_ league: LeagueState, games: [NFLGame]) -> MatchupActivityAttributes.ContentState {
        let mine = league.team.map { Scores.team($0,league:league.snapshot,rules:league.rules,games:games) }
        let opponent = league.opponent.map { Scores.team($0,league:league.snapshot,rules:league.rules,games:games) }
        let myScore = mine?.local ?? mine?.official, theirScore = opponent?.local ?? opponent?.official
        let count = (mine?.total ?? 0) + (opponent?.total ?? 0)
        let outstanding = (mine?.playing ?? 0) + (mine?.remaining ?? 0) + (opponent?.playing ?? 0) + (opponent?.remaining ?? 0)
        let relevantTeams = Set((league.team?.roster ?? []).filter(\.starter).map(\.nflTeam) + (league.opponent?.roster ?? []).filter(\.starter).map(\.nflTeam))
        let active = games.filter { $0.active && (relevantTeams.contains($0.home) || relevantTeams.contains($0.away)) }
        let status = active.first.map { game in
            RefreshPolicy.stale(fetchedAt:game.fetchedAt,active:true) ? "NFL game status delayed" : "\(game.away) @ \(game.home) · \(game.detail)"
        } ?? "\(mine?.playing ?? 0) playing · \(mine?.remaining ?? 0) upcoming"
        let progress: Double = count == 0 ? 0 : min(1,max(0,Double(count-outstanding)/Double(count)))
        let leader: Int
        if let myScore, let theirScore, myScore != theirScore {
            leader = myScore > theirScore ? 1 : -1
        } else {
            leader = 0
        }
        let scoreSource = mine?.local != nil && opponent?.local != nil ? "Local scoring" : "ESPN / partial local"
        return MatchupActivityAttributes.ContentState(
            myScore:myScore?.exact ?? "—",
            opponentScore:theirScore?.exact ?? "—",
            myProjection:mine?.projected?.exact,
            opponentProjection:opponent?.projected?.exact,
            myRemaining:mine?.remaining ?? 0,
            opponentRemaining:opponent?.remaining ?? 0,
            myPlaying:mine?.playing ?? 0,
            opponentPlaying:opponent?.playing ?? 0,
            progress:progress,
            leader:leader,
            status:String(status.prefix(140)),
            updatedAt:league.snapshot.fetchedAt.timeIntervalSince1970,
            scoreSource:scoreSource)
    }
}
