import Foundation
import SwiftUI
import SwiftData
import Observation
import BackgroundTasks
import FantasyCore

struct AppPreferences: Codable, Equatable {
    var onboardingComplete = false
    var remoteEnabled = false
    var backendURL = ""
    var sportsProvider = "espn"
    var accurateFeedConfirmed = false
    var playerMappings: [String:String] = [:]
    var alerts = AlertPreferences()
    var refreshSeconds: Double = 60
    var appearance = "system"
    var deviceID = UUID().uuidString
    var accountAliases = ["default"]
}

struct PlayerHolding: Identifiable {
    var league: LeagueState
    var player: RosterPlayer
    var id: String { league.id + ":" + player.id }
    var score: ScoringResult? {
        player.week(league.snapshot.week)?.stats.map { ScoringEngine.calculate(stats:$0,position:player.scoringPosition,rules:league.rules) }
    }
    var projection: Decimal? {
        guard let stats = player.week(league.snapshot.week)?.projectionStats else { return nil }
        let result = ScoringEngine.calculate(stats:stats,position:player.scoringPosition,rules:league.rules)
        return result.issues.isEmpty ? result.total : nil
    }
}

private struct ESPNAccountSecret: Codable { var s2: String; var swid: String }

@Observable @MainActor final class AppModel {
    static let refreshIdentifier = "com.fantasyglass.refresh"
    static var supportsPushBuild: Bool {
        #if PUSH_ENABLED
        !RuntimeEnvironment.isLiveContainer
        #else
        false
        #endif
    }
    var leagues: [LeagueState] = []
    var gamesByWeek: [String:[NFLGame]] = [:]
    var refreshing = false
    var message: String?
    var remoteStatus = "Not configured"
    var backgroundStatus = "Scheduled opportunistically by iOS"
    var selectedTab = 0
    var route: MatchupRoute?
    private var calculationRevision = 0
    var preferences: AppPreferences {
        didSet {
            let resetBaseline = oldValue.sportsProvider != preferences.sportsProvider || oldValue.playerMappings != preferences.playerMappings || oldValue.accurateFeedConfirmed != preferences.accurateFeedConfirmed
            if resetBaseline {
                calculationRevision += 1
                for index in leagues.indices { leagues[index].event = nil }
            }
            do {
                try repository.store(preferences,key:"preferences")
                if resetBaseline { for league in leagues { try repository.save(league) } }
            }
            catch { message = "Settings could not be saved: \(error.localizedDescription)" }
        }
    }
    let keychain = KeychainStore()
    let repository: LeagueRepository
    let provider: ESPNProvider
    let scoreboard: ESPNScoreboardProvider
    let sportsData: SportsDataIOProvider
    let notifications = NotificationService()
    let remote = RemoteClient()

    init(container: ModelContainer) {
        repository = LeagueRepository(context:container.mainContext)
        let client = HTTPClient()
        provider = ESPNProvider(client:client); scoreboard = ESPNScoreboardProvider(client:client); sportsData = SportsDataIOProvider(client:client)
        preferences = (try? repository.read(AppPreferences.self,key:"preferences")) ?? AppPreferences()
        do {
            leagues = try repository.load()
            gamesByWeek = try repository.read([String:[NFLGame]].self,key:"games") ?? [:]
        } catch { message = "Could not read cached data: \(error.localizedDescription). The stored data has not been deleted." }
    }
    var allGames: [NFLGame] {
        var map: [String:NFLGame] = [:]
        for list in gamesByWeek.values { for game in list { if map[game.id]?.fetchedAt ?? .distantPast < game.fetchedAt { map[game.id] = game } } }
        return map.values.sorted { $0.start < $1.start }
    }
    var holdings: [PlayerHolding] { leagues.flatMap { league in (league.team?.roster ?? []).map { PlayerHolding(league:league,player:$0) } } }
    var groupedPlayers: [String:[PlayerHolding]] { Dictionary(grouping:holdings,by: { "\($0.league.connection.provider):\($0.player.id)" }) }
    var colorScheme: ColorScheme? { preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil }
    func games(for league: LeagueState) -> [NFLGame] { gamesByWeek[weekKey(league.snapshot.season,league.snapshot.week)] ?? [] }
    func game(for holding: PlayerHolding) -> NFLGame? { games(for:holding.league).first { $0.home == holding.player.nflTeam || $0.away == holding.player.nflTeam } }
    func summary(_ team: FantasyTeam, league: LeagueState) -> ScoreSummary { Scores.team(team,league:league.snapshot,rules:league.rules,games:games(for:league)) }
    func stale(_ league: LeagueState) -> Bool {
        let games = games(for:league)
        return league.error != nil || RefreshPolicy.stale(fetchedAt:league.snapshot.fetchedAt,active:games.contains(where: \.active)) || games.contains { RefreshPolicy.stale(fetchedAt:$0.fetchedAt,active:$0.active) }
    }
    private func weekKey(_ season: Int, _ week: Int) -> String { "\(season):\(week)" }
    func credentials(account: String) throws -> ESPNCredentials? {
        guard let text = try keychain.read("espn.\(account)") else { return nil }
        let secret = try JSONDecoder().decode(ESPNAccountSecret.self,from:Data(text.utf8))
        return try ESPNCredentials(s2:secret.s2,swid:secret.swid)
    }
    func saveESPN(account: String, s2: String, swid: String) throws {
        guard !account.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ProviderError.invalidInput("Enter an account alias.") }
        _ = try ESPNCredentials(s2:s2,swid:swid)
        let data = try JSONEncoder().encode(ESPNAccountSecret(s2:s2,swid:swid))
        try keychain.write(String(decoding:data,as:UTF8.self),account:"espn.\(account)")
        if !preferences.accountAliases.contains(account) { preferences.accountAliases.append(account) }
    }
    func clearESPN(account: String) throws {
        try keychain.delete("espn.\(account)")
        Task { await syncRemote() }
    }
    func inspectLeague(id: String, season: Int, account: String) async throws -> LeagueSnapshot {
        try await provider.load(leagueID:id,season:season,credentials:credentials(account:account))
    }
    func connect(snapshot: LeagueSnapshot, teamIDs: Set<Int>, account: String) throws {
        guard !teamIDs.isEmpty else { throw ProviderError.invalidInput("Choose at least one of your teams.") }
        for team in teamIDs {
            let connection = LeagueConnection(leagueID:snapshot.leagueID,season:snapshot.season,teamID:team,accountID:account)
            if let index = leagues.firstIndex(where: { $0.id == connection.id }) {
                leagues[index].snapshot = snapshot; leagues[index].connection = connection; leagues[index].error = nil
                try repository.save(leagues[index])
            } else {
                let state = LeagueState(connection:connection,snapshot:snapshot)
                try repository.save(state); leagues.append(state)
            }
        }
        preferences.onboardingComplete = true
    }
    func remove(_ id: String) async throws {
        if preferences.remoteEnabled, let token = try keychain.read("backend.token") {
            try await remote.remove(id:"\(preferences.deviceID):\(id)",baseURL:preferences.backendURL,token:token)
        }
        try repository.remove(id)
        leagues.removeAll { $0.id == id }
    }
    func saveOverride(_ config: ScoringConfiguration?, leagueID: String) throws {
        guard let index = leagues.firstIndex(where: { $0.id == leagueID }) else { return }
        leagues[index].localOverride = config
        calculationRevision += 1
        // Rule edits must not masquerade as on-field events or stat corrections.
        leagues[index].event = nil
        try repository.save(leagues[index])
        Task { await syncRemote() }
    }
    @discardableResult func refresh() async -> Bool {
        guard !refreshing else { return false }
        refreshing = true
        defer { refreshing = false; scheduleBackgroundRefresh() }
        var imported: [String:Result<LeagueSnapshot,Error>] = [:]
        var fetchedGames: Set<String> = []
        var external: [String:Result<[ExternalPlayerStats],Error>] = [:]
        var successful = true
        for id in leagues.map(\.id) {
            guard !Task.isCancelled, let index = leagues.firstIndex(where: { $0.id == id }) else { successful = false; break }
            var state = leagues[index]
            let revision = calculationRevision
            let connection = state.connection
            let key = "\(connection.accountID):\(connection.season):\(connection.leagueID)"
            if imported[key] == nil {
                do { imported[key] = .success(try await provider.load(leagueID:connection.leagueID,season:connection.season,credentials:credentials(account:connection.accountID))) }
                catch { imported[key] = .failure(error) }
            }
            do {
                guard let result = imported[key] else { continue }
                let fresh = try result.get()
                if fresh.importedRules != state.snapshot.importedRules { state.event = nil }
                state.snapshot = fresh
                state.error = nil
                let gameKey = weekKey(state.snapshot.season,state.snapshot.week)
                if !fetchedGames.contains(gameKey) {
                    fetchedGames.insert(gameKey)
                    do { gamesByWeek[gameKey] = try await scoreboard.games(season:state.snapshot.season,week:state.snapshot.week) }
                    catch { message = "NFL game status could not refresh: \(error.localizedDescription)" }
                }
                if preferences.sportsProvider == "sportsdata" {
                    if !preferences.accurateFeedConfirmed {
                        state.snapshot.warnings.append("SportsDataIO is disabled until you confirm a licensed, accurate production feed. ESPN stats retained.")
                    } else {
                        if external[gameKey] == nil {
                            do {
                                let apiKey = try keychain.read("sportsdata.key") ?? ""
                                external[gameKey] = .success(try await sportsData.playerStats(season:state.snapshot.season,week:state.snapshot.week,apiKey:apiKey))
                            } catch { external[gameKey] = .failure(error) }
                        }
                        if let result = external[gameKey] {
                            do { applySportsData(try result.get(),to:&state) }
                            catch { state.snapshot.warnings.append("SportsDataIO unavailable; ESPN retained. \(error.localizedDescription)") }
                        }
                    }
                }
                // A settings change invalidates this request's calculation context. Keep
                // the edited cache and recompute from fresh source data on the next refresh.
                guard revision == calculationRevision,
                      leagues.contains(where: { $0.id == id && $0.connection == connection }) else { successful = false; continue }
                let frame = EventFrame.make(connection:connection,league:state.snapshot,rules:state.rules,games:games(for:state))
                if !preferences.remoteEnabled {
                    let alerts = EventDetector.detect(previous:state.event,current:frame,preferences:preferences.alerts).filter { !state.delivered.contains($0.id) }
                    do {
                        let delivered = try await notifications.deliver(alerts,connectionID:state.id,matchupID:state.matchup?.id)
                        state.delivered.formUnion(delivered)
                    } catch { message = "Scores refreshed, but a notification could not be scheduled: \(error.localizedDescription)" }
                }
                if state.event?.scope != frame.scope { state.delivered = [] }
                state.event = frame
            } catch {
                successful = false
                if Task.isCancelled { break }
                state.error = error.localizedDescription
            }
            if revision == calculationRevision, let currentIndex = leagues.firstIndex(where: { $0.id == id && $0.connection == connection }) {
                // Preserve a rule edit that happened while a network request was in flight.
                if leagues[currentIndex].localOverride != state.localOverride { state.localOverride = leagues[currentIndex].localOverride; state.event = nil }
                leagues[currentIndex] = state
                do { try repository.save(state) }
                catch { message = "Scores refreshed but could not be cached: \(error.localizedDescription)"; successful = false }
            }
        }
        do { try repository.store(gamesByWeek,key:"games") } catch { message = "Game cache could not be saved: \(error.localizedDescription)" }
        if !Task.isCancelled { await syncRemote() }
        return successful
    }
    private func applySportsData(_ rows: [ExternalPlayerStats], to league: inout LeagueState) {
        let byID = Dictionary(rows.map { ($0.id,$0) },uniquingKeysWith: { _,new in new })
        for ti in league.snapshot.teams.indices {
            for pi in league.snapshot.teams[ti].roster.indices {
                var player = league.snapshot.teams[ti].roster[pi]
                guard let mapping = preferences.playerMappings[player.id], let row = byID[mapping] else { continue }
                let missing = SportsDataIOProvider.missingCategories(for:player,rules:league.rules,external:row)
                guard missing.isEmpty else {
                    league.snapshot.warnings.append("\(player.name): ESPN retained because SportsDataIO lacks \(missing.joined(separator:", ")).")
                    continue
                }
                var week = player.week(league.snapshot.week) ?? PlayerWeek(week:league.snapshot.week)
                week.stats = row.stats
                player.weeks.removeAll { $0.week == league.snapshot.week }; player.weeks.append(week)
                player.source = "SportsDataIO · mapped ID \(row.id)"; player.fetchedAt = row.fetchedAt
                league.snapshot.teams[ti].roster[pi] = player
            }
        }
    }
    func foregroundLoop() async {
        while !Task.isCancelled {
            _ = await refresh()
            let interval = RefreshPolicy.interval(games:allGames,activeInterval:preferences.refreshSeconds)
            do { try await Task.sleep(for:.seconds(interval)) } catch { return }
        }
    }
    func scheduleBackgroundRefresh() {
        guard !RuntimeEnvironment.isLiveContainer else {
            backgroundStatus = "LiveContainer: refresh available while the app is open"
            return
        }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.refreshIdentifier)
        let request = BGAppRefreshTaskRequest(identifier:Self.refreshIdentifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(900)
        do { try BGTaskScheduler.shared.submit(request); backgroundStatus = "Refresh requested; iOS chooses when it runs" }
        catch { backgroundStatus = "Background refresh unavailable: \(error.localizedDescription)" }
    }
    func syncRemote() async {
        guard preferences.remoteEnabled else { return }
        guard Self.supportsPushBuild else { remoteStatus = "This build has no APNs entitlement. Use the Push build with paid provisioning."; return }
        do {
            guard let token = try keychain.read("backend.token") else { throw ProviderError.invalidInput("Enter your backend owner token in Settings.") }
            for state in leagues {
                let auth = try credentials(account:state.connection.accountID)
                let payload = RemoteSubscription(id:"\(preferences.deviceID):\(state.id)",connectionID:state.id,leagueID:state.connection.leagueID,
                    season:state.connection.season,teamID:state.connection.teamID,matchupID:state.matchup?.id,
                    deviceToken:try keychain.read("apns.deviceToken"),s2:auth?.s2,swid:auth?.swid,
                    rules:state.localOverride?.rules.map(RemoteRule.init),ruleIssues:state.localOverride?.issues ?? [],
                    enabledAlerts:preferences.alerts.enabled.map(\.rawValue),thresholds:preferences.alerts.thresholds.mapValues(\.exact),
                    sportsDataKey:preferences.sportsProvider == "sportsdata" ? try keychain.read("sportsdata.key") : nil,
                    playerMappings:preferences.playerMappings,accurateFeedConfirmed:preferences.accurateFeedConfirmed)
                try await remote.save(payload,baseURL:preferences.backendURL,token:token)
            }
            remoteStatus = "Subscriptions saved. APNs delivery still depends on provisioning and iOS."
        } catch { remoteStatus = error.localizedDescription }
    }
    func disableRemote() async throws {
        if let token = try keychain.read("backend.token") {
            for league in leagues { try await remote.remove(id:"\(preferences.deviceID):\(league.id)",baseURL:preferences.backendURL,token:token) }
        }
        preferences.remoteEnabled = false
        remoteStatus = "Disabled; server subscriptions removed"
    }
    func open(_ url: URL) {
        guard let link = MatchupLink.parse(url) else { return }
        selectedTab = 2
        if leagues.contains(where: { $0.id == link.connection }) { route = .init(connectionID:link.connection,matchupID:link.matchup) }
        else { message = "This matchup's league is no longer connected on this device." }
    }
}

struct MatchupRoute: Identifiable {
    var connectionID: String
    var matchupID: String
    var id: String { "\(connectionID):\(matchupID)" }
}
