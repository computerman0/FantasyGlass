import SwiftUI
import FantasyCore

struct RootView: View {
    @Bindable var model: AppModel
    @State private var showSetup = false
    var body: some View {
        TabView(selection:$model.selectedTab) {
            Tab("Dashboard",systemImage:"square.grid.2x2.fill",value:0) { DashboardView(model:model) }
            Tab("Players",systemImage:"person.3.fill",value:1) { PlayersView(model:model) }
            Tab("Matchups",systemImage:"sportscourt.fill",value:2) { MatchupsView(model:model) }
            Tab("Leagues",systemImage:"trophy.fill",value:3) { LeaguesView(model:model) }
            Tab("Settings",systemImage:"gearshape.fill",value:4) { SettingsView(model:model) }
        }
        .tint(.cyan)
        .sensoryFeedback(.selection,trigger:model.selectedTab)
        .sensoryFeedback(.success,trigger:model.activities.trackedConnection)
        .sheet(isPresented:$showSetup) { SetupAssistantView(model:model) }
        .sheet(item:$model.route) { route in
            NavigationStack { MatchupDetailView(model:model,connectionID:route.connectionID,requestedMatchupID:route.matchupID).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { model.route = nil } } } }
        }
        .alert("FantasyGlass",isPresented:Binding(get: { model.message != nil },set: { if !$0 { model.message = nil } })) {
            Button("OK",role:.cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onAppear { showSetup = !model.preferences.onboardingComplete }
    }
}

struct DashboardView: View {
    let model: AppModel
    @State private var connect = false
    var body: some View {
        NavigationStack {
            Group {
                if model.leagues.isEmpty { EmptyLeaguesView { connect = true } }
                else {
                    List {
                        Section {
                            VStack(alignment:.leading,spacing:12) {
                                Text("Every team.\nOne game day.").font(.largeTitle.bold())
                                HStack(spacing:20) {
                                    Label("\(model.leagues.count) teams",systemImage:"trophy")
                                    Label("\(model.groupedPlayers.count) players",systemImage:"person.3")
                                }.font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical,8)
                        }
                        ForEach(model.leagues) { league in
                            Section {
                                NavigationLink { MatchupDetailView(model:model,connectionID:league.id) } label: { MatchupCard(league:league,model:model) }
                            }
                        }
                        let live = model.groupedPlayers.values.compactMap { $0.first }.filter { model.game(for:$0)?.active == true }
                        if !live.isEmpty {
                            Section("On the field") {
                                ForEach(live.sorted { $0.player.name < $1.player.name }) { holding in
                                    NavigationLink { PlayerDetailView(model:model,playerID:holding.player.id) } label: { PlayerRow(holding:holding,model:model) }
                                }
                            }
                        }
                        Section { Text("Win probability is unavailable: no calibrated probability model is configured. Projections are provider estimates, not guarantees.").font(.footnote).foregroundStyle(.secondary) }
                    }.refreshable { await model.refresh() }
                }
            }
            .navigationTitle("FantasyGlass")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button("Connect league",systemImage:"plus") { connect = true }.buttonStyle(.glass) }
                ToolbarItem(placement:.topBarLeading) { if model.refreshing { ProgressView().accessibilityLabel("Refreshing scores") } }
            }
            .sheet(isPresented:$connect) { LeagueConnectView(model:model) }
        }
    }
}
