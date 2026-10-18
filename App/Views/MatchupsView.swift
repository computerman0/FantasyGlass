import SwiftUI
import FantasyCore

struct MatchupsView: View {
    let model: AppModel
    var body: some View {
        NavigationStack {
            List {
                if model.leagues.isEmpty { ContentUnavailableView("No matchups yet",systemImage:"sportscourt",description:Text("Connect a league in the Leagues tab.")) }
                if let id = model.leagues.first(where: { $0.id == model.preferences.defaultMatchup })?.id {
                    Section { Button("Track default matchup",systemImage:"capsule.inset.filled") { Task { await model.track(id) } }.buttonStyle(.glass) }
                }
                ForEach(model.leagues) { league in
                    Section {
                        NavigationLink { MatchupDetailView(model:model,connectionID:league.id) } label: { MatchupCard(league:league,model:model) }
                        if league.opponent != nil {
                            Button(model.activities.trackedConnection == league.id ? "Tracking in Dynamic Island" : "Track in Dynamic Island",systemImage:"capsule.inset.filled") { Task { await model.track(league.id) } }
                                .buttonStyle(.glass).disabled(model.activities.trackedConnection == league.id)
                        }
                    }
                }
                if model.activities.trackedConnection != nil { Button("End Live Activity",role:.destructive) { Task { await model.endTracking() } } }
                Section { Text(model.preferences.remoteEnabled ? model.remoteStatus : "Local activity updates occur while the app runs. iOS may suspend updates when you leave the app. Configure the optional APNs backend for remote updates.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Matchups").refreshable { await model.refresh() }
        }
    }
}

struct MatchupDetailView: View {
    let model: AppModel
    let connectionID: String
    var requestedMatchupID: String? = nil
    private var league: LeagueState? { model.leagues.first { $0.id == connectionID } }
    var body: some View {
        Group {
            if let league {
                List {
                    if let requestedMatchupID, requestedMatchupID != league.matchup?.id {
                        Section {
                            if let historical = league.snapshot.schedule.first(where: { $0.id == requestedMatchupID }) {
                                Text("Tracked matchup · period \(historical.period)").font(.headline)
                                Text("\(league.snapshot.team(historical.homeID)?.name ?? "Home") \(historical.homeOfficial?.exact ?? "—") — \(historical.awayID.flatMap(league.snapshot.team)?.name ?? "Bye") \(historical.awayOfficial?.exact ?? "—")")
                                Text("Official archived result. Current-week lineup is shown below.").font(.caption).foregroundStyle(.secondary)
                            } else { Text("The tracked matchup is no longer in the cached schedule. Refresh to retrieve it.") }
                        }
                    }
                    Section { MatchupCard(league:league,model:model) }
                    if league.opponent != nil {
                        Section {
                            Button("Track in Dynamic Island",systemImage:"capsule.inset.filled") { Task { await model.track(league.id) } }.buttonStyle(.glassProminent)
                            Button(model.preferences.defaultMatchup == league.id ? "Default matchup selected" : "Use as default matchup",systemImage:"star") { model.preferences.defaultMatchup = league.id }
                            if model.activities.trackedConnection == league.id { Button("End tracking",role:.destructive) { Task { await model.endTracking() } } }
                        }
                    }
                    if let mine = league.team { roster(mine,league:league) }
                    if let opponent = league.opponent { roster(opponent,league:league) }
                    let warnings = Array(Set(league.snapshot.warnings + (league.team.map { model.summary($0,league:league).warnings } ?? []))).sorted()
                    if !warnings.isEmpty { Section("Data notes") { ForEach(warnings,id:\.self) { Text($0).font(.footnote).foregroundStyle(.orange) } } }
                    Section { Text("Local scores use this league's rules and retrieved raw statistics. ESPN totals remain visible for comparison. Projection totals use pregame projection stat lines when supplied; win probability is unavailable.").font(.footnote).foregroundStyle(.secondary) }
                }.refreshable { await model.refresh() }
            } else { ContentUnavailableView("League unavailable",systemImage:"trophy",description:Text("Reconnect this league to view the matchup.")) }
        }.navigationTitle("Matchup").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func roster(_ team: FantasyTeam, league: LeagueState) -> some View {
        Section(team.name) {
            ForEach(team.roster.sorted { $0.starter && !$1.starter }) { player in
                let holding = PlayerHolding(league:league,player:player)
                NavigationLink { PlayerDetailView(model:model,playerID:player.id,additional:holding) } label: { PlayerRow(holding:holding,model:model) }
            }
        }
    }
}
