import SwiftUI
import FantasyCore

enum PlayerFilter: String, CaseIterable, Identifiable {
    case all = "All players", playing = "Playing", upcoming = "Upcoming", finished = "Finished", injured = "Injured", starters = "Starters", bench = "Bench"
    var id: String { rawValue }
}
enum PlayerSort: String, CaseIterable, Identifiable {
    case points = "Fantasy points", projected = "Projected points", time = "Game time", name = "Player name"
    var id: String { rawValue }
}
struct PlayersView: View {
    let model: AppModel
    @State private var filter = PlayerFilter.all
    @State private var sort = PlayerSort.points
    @State private var leagueID = ""
    @State private var gameID = ""
    @State private var search = ""
    private var groups: [[PlayerHolding]] {
        let holdings = model.holdings.filter { holding in
            let game = model.game(for:holding)
            let matches: Bool = switch filter {
            case .all: true
            case .playing: game?.active == true
            case .upcoming: game?.remaining == true
            case .finished: game?.phase == .final
            case .injured: holding.player.injured
            case .starters: holding.player.starter
            case .bench: !holding.player.starter
            }
            return matches && (leagueID.isEmpty || holding.league.id == leagueID) && (gameID.isEmpty || game?.id == gameID) && (search.isEmpty || holding.player.name.localizedCaseInsensitiveContains(search))
        }
        let values = Dictionary(grouping:holdings,by:\.player.id).values.map { $0.sorted { $0.league.snapshot.name < $1.league.snapshot.name } }
        return values.sorted { a,b in
            guard let x = a.first, let y = b.first else { return false }
            switch sort {
            case .points:
                let left = a.compactMap { $0.score?.issues.isEmpty == true ? $0.score?.total : nil }.max()
                let right = b.compactMap { $0.score?.issues.isEmpty == true ? $0.score?.total : nil }.max()
                if left != right { return right == nil || (left != nil && left! > right!) }
            case .projected:
                let left = a.compactMap(\.projection).max(), right = b.compactMap(\.projection).max()
                if left != right { return right == nil || (left != nil && left! > right!) }
            case .time:
                let left = model.game(for:x)?.start ?? .distantFuture, right = model.game(for:y)?.start ?? .distantFuture
                if left != right { return left < right }
            case .name: break
            }
            return x.player.name.localizedCaseInsensitiveCompare(y.player.name) == .orderedAscending
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show",selection:$filter) { ForEach(PlayerFilter.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("League",selection:$leagueID) {
                        Text("Every league").tag("")
                        ForEach(model.leagues) { Text("\($0.snapshot.name) · \($0.team?.name ?? "")").tag($0.id) }
                    }
                    Picker("NFL game",selection:$gameID) {
                        Text("Every game").tag("")
                        ForEach(model.allGames) { Text("\($0.away) @ \($0.home) · \($0.start.formatted(date:.abbreviated,time:.omitted))").tag($0.id) }
                    }
                }
                Section {
                    ForEach(groups,id:\.first!.player.id) { holdings in
                        if let first = holdings.first {
                            DisclosureGroup {
                                NavigationLink("Player details and scoring",systemImage:"chart.bar.xaxis") { PlayerDetailView(model:model,playerID:first.player.id) }
                                ForEach(holdings) { holding in
                                    VStack(alignment:.leading,spacing:4) {
                                        Text("\(holding.league.snapshot.name) · \(holding.player.starter ? "Starter" : "Bench")").font(.subheadline)
                                        HStack {
                                            Text(holding.league.rules.name).font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            ScoreText(value:holding.score?.issues.isEmpty == true ? holding.score?.total : nil)
                                        }
                                    }
                                }
                            } label: {
                                VStack(alignment:.leading,spacing:4) {
                                    PlayerRow(holding:first,model:model)
                                    Text("\(holdings.count) team\(holdings.count == 1 ? "" : "s") · highest local score \(holdings.compactMap { $0.score?.issues.isEmpty == true ? $0.score?.total : nil }.max()?.exact ?? "—")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if groups.isEmpty { ContentUnavailableView.search(text:search.isEmpty ? "these filters" : search) }
                } footer: { Text("A player appears once. Expand to compare exact points in each league. Points sorting uses the highest local league score; missing scores sort last.") }
            }
            .navigationTitle("Players").searchable(text:$search,prompt:"Find a player")
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Menu("Sort",systemImage:"arrow.up.arrow.down") { Picker("Sort",selection:$sort) { ForEach(PlayerSort.allCases) { Text($0.rawValue).tag($0) } } } } }
            .refreshable { await model.refresh() }
        }
    }
}

struct PlayerRow: View {
    let holding: PlayerHolding
    let model: AppModel
    var body: some View {
        HStack(spacing:12) {
            PlayerAvatar(player:holding.player)
            VStack(alignment:.leading,spacing:4) {
                Text(holding.player.name).font(.headline)
                Text("\(holding.player.nflTeam) · \(holding.player.position) · \(holding.player.starter ? "Starter" : "Bench")").font(.caption).foregroundStyle(.secondary)
                if let game = model.game(for:holding) {
                    Text("vs \(game.opponent(of:holding.player.nflTeam)) · \(game.detail)" + (RefreshPolicy.stale(fetchedAt:game.fetchedAt,active:game.active) ? " · Cached status" : ""))
                        .font(.caption).foregroundStyle(game.active && !model.stale(holding.league) ? Color.green : Color.secondary)
                } else { Text("No game status available").font(.caption).foregroundStyle(.secondary) }
                if holding.player.injured { Label(holding.player.injury,systemImage:"cross.case.fill").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength:8)
            VStack(alignment:.trailing,spacing:3) {
                ScoreText(value:holding.score?.issues.isEmpty == true ? holding.score?.total : holding.player.week(holding.league.snapshot.week)?.official)
                Text(holding.score?.issues.isEmpty == true ? "Local" : "ESPN").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical,4)
    }
}

struct PlayerDetailView: View {
    let model: AppModel
    let playerID: String
    var additional: PlayerHolding? = nil
    @State private var threshold = ""
    @State private var mapping = ""
    private var holdings: [PlayerHolding] {
        var found = model.holdings.filter { $0.player.id == playerID }
        if let additional, !found.contains(where: { $0.id == additional.id }) { found.append(additional) }
        return found
    }
    var body: some View {
        Group {
            if let first = holdings.first {
                List {
                    Section {
                        HStack(spacing:16) {
                            PlayerAvatar(player:first.player,size:72)
                            VStack(alignment:.leading,spacing:6) {
                                Text(first.player.name).font(.title2.bold())
                                Text("\(first.player.nflTeam) · \(first.player.position)" + (first.player.jersey.map { " · #\($0)" } ?? ""))
                                if let game = model.game(for:first) {
                                    Text("vs \(game.opponent(of:first.player.nflTeam)) · \(game.detail)").font(.subheadline)
                                    Text("Quarter \(game.period) · \(game.clock)").font(.caption).foregroundStyle(.secondary)
                                }
                                if first.player.injured { Text(first.player.injury).foregroundStyle(.orange) }
                            }
                        }.padding(.vertical,8)
                    }
                    ForEach(holdings) { holding in
                        Section("\(holding.league.snapshot.name) · \(holding.league.snapshot.season) W\(holding.league.snapshot.week) · \(holding.player.starter ? "Starter" : "Bench")") {
                            if let score = holding.score {
                                LabeledContent("Local points") { ScoreText(value:score.total,large:true) }
                                if !score.issues.isEmpty { ForEach(score.issues,id:\.self) { Text("Partial calculation: \($0)").foregroundStyle(.orange).font(.caption) } }
                                if let projected = holding.projection { LabeledContent("Projected",value:projected.exact) }
                                if let official = holding.player.week(holding.league.snapshot.week)?.official {
                                    LabeledContent("ESPN official",value:official.exact)
                                    if official != score.total { LabeledContent("Local − ESPN",value:(score.total-official).exact).foregroundStyle(.orange) }
                                }
                                ForEach(score.contributions) { item in
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(item.label).font(.subheadline.weight(.medium))
                                        Text("\(item.units.exact) × \(item.rate.exact) = \(item.points.exact) points").font(.callout.monospacedDigit()).textSelection(.enabled)
                                        if item.mode != .linear { Text("Raw value \(item.raw.exact) · \(item.mode.rawValue) rule").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                if score.contributions.isEmpty { Text("No scored statistics reported yet.").foregroundStyle(.secondary) }
                            } else { Text("Raw statistics have not been supplied for this week. A local score is unavailable.").foregroundStyle(.secondary) }
                            SourceStatus(date:holding.player.fetchedAt,stale:model.stale(holding.league),source:holding.player.source)
                            DisclosureGroup("Raw NFL statistics") {
                                ForEach((holding.player.week(holding.league.snapshot.week)?.stats ?? [:]).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending },id:\.key) { stat in
                                    LabeledContent("\(StatCatalog.label(stat.key)) [\(stat.key)]",value:stat.value.exact).font(.caption).textSelection(.enabled)
                                }
                            }
                            DisclosureGroup("Weekly and season history") {
                                ForEach(holding.player.weeks.filter { $0.week > 0 }.sorted { $0.week < $1.week },id:\.week) { week in
                                    HStack {
                                        Text("Week \(week.week)")
                                        Spacer()
                                        if let stats = week.stats {
                                            Text(ScoringEngine.calculate(stats:stats,position:holding.player.scoringPosition,rules:holding.league.rules).total.exact).monospacedDigit()
                                        } else { Text("No raw stats").foregroundStyle(.secondary) }
                                    }
                                }
                                if let season = holding.player.week(0)?.official { LabeledContent("ESPN season total",value:season.exact) }
                                Text("History includes only weeks returned by the provider. Historical local totals use your current local rules. Season totals remain ESPN's official aggregate.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Track a point threshold") {
                        TextField("Fantasy points, e.g. 20",text:$threshold).keyboardType(.numbersAndPunctuation)
                        Button("Save threshold") {
                            guard let value = Decimal.parse(threshold) else { model.message = "Enter a valid decimal point threshold."; return }
                            model.preferences.alerts.thresholds[playerID] = value
                            model.preferences.alerts.enabled.insert(.threshold)
                            Task { await model.syncRemote() }
                        }
                        Button("Remove threshold",role:.destructive) {
                            model.preferences.alerts.thresholds.removeValue(forKey:playerID)
                            Task { await model.syncRemote() }
                        }
                    }
                    if model.preferences.sportsProvider == "sportsdata" {
                        Section("SportsDataIO player mapping") {
                            Text("ESPN player ID: \(playerID). Enter this same player's numeric SportsDataIO PlayerID from its roster response. Matching by name is never assumed.").font(.caption)
                            TextField("SportsDataIO PlayerID",text:$mapping).keyboardType(.numberPad)
                            Button("Save mapping") {
                                guard !mapping.isEmpty, mapping.allSatisfy(\.isNumber) else { model.message = "Enter a numeric SportsDataIO PlayerID."; return }
                                model.preferences.playerMappings[playerID] = mapping
                                Task { await model.refresh() }
                            }
                            Button("Remove mapping",role:.destructive) {
                                model.preferences.playerMappings.removeValue(forKey:playerID)
                                Task { await model.refresh() }
                            }
                        }
                    }
                    Section { Text("Timestamps report when FantasyGlass retrieved data. The upstream provider may be delayed even after a successful refresh.").font(.footnote).foregroundStyle(.secondary) }
                }
            } else { ContentUnavailableView("Player unavailable",systemImage:"person.crop.circle.badge.questionmark") }
        }
        .navigationTitle("Player").navigationBarTitleDisplayMode(.inline)
        .onAppear { threshold = model.preferences.alerts.thresholds[playerID]?.exact ?? ""; mapping = model.preferences.playerMappings[playerID] ?? "" }
    }
}
