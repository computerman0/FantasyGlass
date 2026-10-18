import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ESPNProvider: FantasyProvider {
    public let client: HTTPClient
    public init(client: HTTPClient = HTTPClient()) { self.client = client }
    public func load(leagueID: String, season: Int, credentials: ESPNCredentials?, week: Int? = nil) async throws -> LeagueSnapshot {
        guard !leagueID.isEmpty, leagueID.count <= 20, leagueID.allSatisfy({ $0.isASCII && $0.isNumber }), (2018...2100).contains(season) else { throw ProviderError.invalidInput("Use a numeric ESPN league ID (at most 20 digits) and a season from 2018 onward.") }
        var url = URLComponents(string: "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/\(season)/segments/0/leagues/\(leagueID)")!
        url.queryItems = ["mSettings", "mTeam", "mRoster", "mMatchup", "mMatchupScore"].map { URLQueryItem(name: "view", value: $0) }
        if let week { url.queryItems?.append(.init(name: "scoringPeriodId", value: String(week))) }
        var request = URLRequest(url: url.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credentials { request.setValue("espn_s2=\(credentials.s2); SWID=\(credentials.swid)", forHTTPHeaderField: "Cookie") }
        return try Self.decode(await client.data(request), expectedLeagueID: leagueID, season: season)
    }

    public static func decode(_ data: Data, expectedLeagueID: String, season: Int, now: Date = .now) throws -> LeagueSnapshot {
        let root: JSONValue
        do { root = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw ProviderError.invalidResponse("ESPN returned non-JSON content, possibly a sign-in page.") }
        guard root["id"].textID == expectedLeagueID, root["seasonId"].int == season,
              !root["teams"].array.isEmpty else { throw ProviderError.invalidResponse("League ID, season, or teams are missing.") }
        let week = root["scoringPeriodId"].int ?? root["status"]["latestScoringPeriod"].int ?? 1
        let period = root["status"]["currentMatchupPeriod"].int ?? week
        let settings = root["settings"]["scoringSettings"]
        var issues: [String] = []
        let rules = settings["scoringItems"].array.compactMap { item -> ScoringRule? in
            guard let key = item["statId"].textID, let points = item["points"].decimal else {
                issues.append("Malformed ESPN scoring item"); return nil
            }
            if item["isReverseItem"].bool { issues.append("Reverse-scoring category \(key) requires review.") }
            return ScoringRule(id: key, stat: key, label: StatCatalog.label(key), multiplier: points, positionMultipliers: item["pointsOverrides"].decimals)
        }
        if rules.isEmpty { issues.append("ESPN did not supply scoring rules. No local team score is asserted.") }
        if (settings["homeTeamBonus"].decimal ?? 0) != 0 || (settings["playoffHomeTeamBonus"].decimal ?? 0) != 0 { issues.append("Home-team bonuses require review against official matchup adjustments.") }
        let type = settings["scoringType"].string ?? "UNKNOWN"
        if type != "H2H_POINTS" { issues.append("Scoring type \(type) is not a validated head-to-head points format.") }
        let reception = rules.first { $0.stat == "53" || $0.stat == "41" }?.multiplier ?? 0
        let format = reception == 1 ? "PPR" : reception == Decimal(string: "0.5")! ? "Half PPR" : reception == 0 ? "Standard / custom" : "Custom PPR \(reception.exact)"
        let config = ScoringConfiguration(name: format, rules: rules, issues: issues)
        let periods = root["settings"]["scheduleSettings"]["matchupPeriods"]
        let schedule = root["schedule"].array.compactMap { match -> FantasyMatchup? in
            guard let id = match["id"].textID, let homeID = match["home"]["teamId"].int else { return nil }
            let p = match["matchupPeriodId"].int ?? 0
            return FantasyMatchup(id: id, period: p, homeID: homeID, awayID: match["away"]["teamId"].int,
                homeOfficial: match["home"]["totalPoints"].decimal, awayOfficial: match["away"]["totalPoints"].decimal,
                homeAdjustment: match["home"]["adjustment"].decimal ?? 0, awayAdjustment: match["away"]["adjustment"].decimal ?? 0,
                winner: match["winner"].string ?? "UNDECIDED", weeks: periods[String(p)].array.compactMap(\.int))
        }
        var rosterOverrides: [Int: [JSONValue]] = [:]
        for match in root["schedule"].array where match["matchupPeriodId"].int == period {
            for side in ["home", "away"] {
                let entries = match[side]["rosterForCurrentScoringPeriod"]["entries"].array
                if let teamID = match[side]["teamId"].int, !entries.isEmpty { rosterOverrides[teamID] = entries }
            }
        }
        let teams = root["teams"].array.compactMap { team -> FantasyTeam? in
            guard let id = team["id"].int else { return nil }
            let name = team["name"].string ?? [team["location"].string, team["nickname"].string].compactMap { $0 }.joined(separator: " ")
            let record = team["record"]["overall"]
            return FantasyTeam(id: id, name: name.isEmpty ? "Team \(id)" : name,
                wins: record["wins"].int ?? 0, losses: record["losses"].int ?? 0, ties: record["ties"].int ?? 0,
                rank: team["playoffSeed"].int, owners: team["owners"].array.compactMap(\.string),
                roster: (rosterOverrides[id] ?? team["roster"]["entries"].array).compactMap { decodePlayer($0, season: season, now: now) })
        }
        return LeagueSnapshot(leagueID: expectedLeagueID, season: season, name: root["settings"]["name"].string ?? "League \(expectedLeagueID)",
            week: week, matchupPeriod: period, teams: teams, schedule: schedule, importedRules: config, fetchedAt: now, warnings: issues)
    }

    private static func decodePlayer(_ entry: JSONValue, season: Int, now: Date) -> RosterPlayer? {
        let p = entry["playerPoolEntry"]["player"]
        guard let id = p["id"].textID, let name = p["fullName"].string else { return nil }
        var history: [Int: PlayerWeek] = [:]
        for line in p["stats"].array where line["seasonId"].int == season && line["statSplitTypeId"].int != 2 {
            guard let week = line["scoringPeriodId"].int else { continue }
            var item = history[week] ?? PlayerWeek(week: week)
            let stats = line["stats"].decimals
            if line["statSourceId"].int == 0 {
                item.stats = stats.isEmpty ? nil : stats; item.official = line["appliedTotal"].decimal
            } else if line["statSourceId"].int == 1 {
                item.projectionStats = stats.isEmpty ? nil : stats; item.projected = line["appliedTotal"].decimal
            }
            history[week] = item
        }
        let pos = p["defaultPositionId"].int ?? -1
        return RosterPlayer(id: id, name: name, nflTeam: StatCatalog.teams[p["proTeamId"].int ?? 0] ?? "FA",
            position: StatCatalog.positions[pos] ?? "IDP", scoringPosition: StatCatalog.scoringPositions[pos] ?? String(pos),
            slot: entry["lineupSlotId"].int ?? 20, jersey: p["jersey"].textID,
            photoURL: p["headshot"]["href"].string.flatMap(URL.init(string:)), injury: p["injuryStatus"].string ?? "UNKNOWN",
            weeks: history.values.sorted { $0.week < $1.week }, fetchedAt: now)
    }
}

public struct ESPNScoreboardProvider: SportsDataProvider {
    public let client: HTTPClient
    public init(client: HTTPClient = HTTPClient()) { self.client = client }
    public func games(season: Int, week: Int) async throws -> [NFLGame] {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=\(season)&seasontype=2&week=\(week)&limit=100")!
        return try Self.decode(await client.data(URLRequest(url: url)))
    }
    public static func decode(_ data: Data, now: Date = .now) throws -> [NFLGame] {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .array = root["events"] else { throw ProviderError.invalidResponse("Missing NFL events array") }
        return root["events"].array.compactMap { event in
            guard let id = event["id"].textID, let competition = event["competitions"].array.first else { return nil }
            let competitors = competition["competitors"].array
            guard let home = competitors.first(where: { $0["homeAway"].string == "home" })?["team"]["abbreviation"].string,
                  let away = competitors.first(where: { $0["homeAway"].string == "away" })?["team"]["abbreviation"].string,
                  let rawDate = event["date"].string, let date = parseDate(rawDate) else { return nil }
            let status = event["status"], type = status["type"], name = type["name"].string ?? ""
            let phase: GamePhase = switch name {
            case "STATUS_HALFTIME": .halftime
            case "STATUS_POSTPONED", "STATUS_DELAYED", "STATUS_SUSPENDED": .postponed
            case "STATUS_CANCELED": .canceled
            default: type["completed"].bool ? .final : type["state"].string == "in" ? .live : type["state"].string == "pre" ? .scheduled : .unknown
            }
            return NFLGame(id: id, home: home == "WSH" ? "WSH" : home, away: away, start: date, phase: phase,
                detail: type["detail"].string ?? "Status unavailable", period: status["period"].int ?? 0, clock: status["displayClock"].string ?? "", fetchedAt: now)
        }
    }
    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from:value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from:value) { return date }
        // ESPN also emits minute-resolution ISO 8601 timestamps such as 2025-10-12T13:30Z.
        let minutes = DateFormatter(); minutes.locale = Locale(identifier:"en_US_POSIX")
        minutes.timeZone = TimeZone(secondsFromGMT:0); minutes.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return minutes.date(from:value)
    }
}
