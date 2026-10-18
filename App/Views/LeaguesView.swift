import SwiftUI
import FantasyCore

struct LeaguesView: View {
    let model: AppModel
    @State private var connect = false
    var body: some View {
        NavigationStack {
            Group {
                if model.leagues.isEmpty { EmptyLeaguesView { connect = true } }
                else {
                    List(model.leagues) { league in
                        NavigationLink { LeagueDetailView(model:model,connectionID:league.id) } label: {
                            VStack(alignment:.leading,spacing:6) {
                                Label(league.snapshot.name,systemImage:"trophy.fill").font(.headline)
                                Text(league.team?.name ?? "Team unavailable")
                                Text("\(league.snapshot.season) · \(league.rules.name) · \(league.localOverride == nil ? "Imported rules" : "Local override")").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical,6)
                        }
                    }.refreshable { await model.refresh() }
                }
            }.navigationTitle("Leagues")
                .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Connect league",systemImage:"plus") { connect = true }.buttonStyle(.glass) } }
                .sheet(isPresented:$connect) { LeagueConnectView(model:model) }
        }
    }
}

struct LeagueDetailView: View {
    let model: AppModel
    let connectionID: String
    @State private var editing = false
    @State private var removing = false
    @Environment(\.dismiss) private var dismiss
    private var league: LeagueState? { model.leagues.first { $0.id == connectionID } }
    var body: some View {
        Group {
            if let league {
                List {
                    Section {
                        LabeledContent("My team",value:league.team?.name ?? "Unavailable")
                        LabeledContent("ESPN league ID",value:league.connection.leagueID).textSelection(.enabled)
                        LabeledContent("Season",value:String(league.connection.season))
                        LabeledContent("Account alias",value:league.connection.accountID)
                        SourceStatus(date:league.snapshot.fetchedAt,stale:model.stale(league))
                    }
                    Section("Scoring") {
                        LabeledContent("Active configuration",value:league.rules.name)
                        Text(league.localOverride == nil ? "Using imported ESPN scoring rules." : "Local overrides are active. ESPN settings are unchanged.").font(.footnote).foregroundStyle(.secondary)
                        Button("Inspect and edit local scoring",systemImage:"slider.horizontal.3") { editing = true }.buttonStyle(.glass)
                        DisclosureGroup("Imported ESPN rules (read only)") {
                            ForEach(league.snapshot.importedRules.rules) { rule in
                                VStack(alignment:.leading,spacing:4) {
                                    LabeledContent(rule.label,value:rule.multiplier.exact)
                                    if !rule.positionMultipliers.isEmpty { Text("Position rates: " + rule.positionMultipliers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.exact)" }.joined(separator:", ")).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    Section("Standings") {
                        ForEach(league.snapshot.teams.sorted { ($0.rank ?? 999) < ($1.rank ?? 999) }) { team in
                            LabeledContent("\(team.rank.map { "\($0). " } ?? "")\(team.name)",value:team.record)
                        }
                    }
                    Section("My schedule") {
                        ForEach(league.snapshot.schedule.filter { $0.contains(league.connection.teamID) }.sorted { $0.period < $1.period }) { match in
                            let opposingID = match.homeID == league.connection.teamID ? match.awayID : match.homeID
                            VStack(alignment:.leading,spacing:5) {
                                Text("Period \(match.period) · vs \(opposingID.flatMap(league.snapshot.team)?.name ?? "Bye")").font(.subheadline)
                                Text("Home \(match.homeOfficial?.exact ?? "—") · Away \(match.awayOfficial?.exact ?? "—") · \(match.winner)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !league.snapshot.warnings.isEmpty { Section("Import notes") { ForEach(league.snapshot.warnings,id:\.self) { Text($0).font(.footnote).foregroundStyle(.orange) } } }
                    Section { Button("Disconnect this team",role:.destructive) { removing = true } }
                }
                .sheet(isPresented:$editing) { ScoringEditorView(model:model,league:league) }
                .confirmationDialog("Disconnect this team and delete its local cache?",isPresented:$removing,titleVisibility:.visible) {
                    Button("Disconnect",role:.destructive) { Task { do { try await model.remove(connectionID); dismiss() } catch { model.message = error.localizedDescription } } }
                }
            } else { ContentUnavailableView("League disconnected",systemImage:"trophy") }
        }.navigationTitle(league?.snapshot.name ?? "League").navigationBarTitleDisplayMode(.inline)
    }
}

struct ScoringEditorView: View {
    let model: AppModel
    let league: LeagueState
    @State private var draft: ScoringConfiguration
    @State private var acknowledged = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, league: LeagueState) {
        self.model = model; self.league = league
        _draft = State(initialValue:league.rules)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Changes apply only in FantasyGlass. Imported ESPN rules are preserved separately.").font(.footnote).foregroundStyle(.secondary)
                    TextField("Configuration name",text:$draft.name)
                    Menu("Start from a preset",systemImage:"list.bullet.rectangle") {
                        Button("Standard") { draft = .standard() }
                        Button("Half PPR") { draft = .standard(ppr:Decimal(string:"0.5")!) }
                        Button("Full PPR") { draft = .standard(ppr:1) }
                        Button("Imported ESPN rules") { draft = league.snapshot.importedRules }
                    }
                }
                Section("Rules") {
                    ForEach($draft.rules) { $rule in
                        NavigationLink { RuleEditorView(rule:$rule) } label: {
                            VStack(alignment:.leading,spacing:4) {
                                LabeledContent(rule.label,value:rule.multiplier.exact)
                                Text("Stat \(rule.stat) · \(rule.mode.rawValue)" + (rule.positionMultipliers.isEmpty ? "" : " · Position overrides")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { draft.rules.remove(atOffsets:$0) }
                    Button("Add scoring rule",systemImage:"plus") { draft.rules.append(.init(stat:"3",label:"Passing yards",multiplier:0)) }
                }
                if !draft.issues.isEmpty {
                    Section("Rules requiring review") {
                        ForEach(draft.issues,id:\.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                        Toggle("I have resolved these issues in my local rules",isOn:$acknowledged)
                    }
                }
                Section { Button("Restore imported ESPN scoring",role:.destructive) { save(nil) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Local scoring").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Save") {
                        guard !draft.name.isEmpty, !draft.rules.isEmpty, draft.rules.count <= 256 else { error = "A name and 1–256 rules are required."; return }
                        if acknowledged { draft.issues = [] }
                        let check = ScoringEngine.calculate(stats:[:],position:"0",rules:draft)
                        let newIssues = check.issues.filter { !draft.issues.contains($0) }
                        guard newIssues.isEmpty else { error = newIssues.joined(separator:"\n"); return }
                        save(draft)
                    }
                }
            }
        }
    }
    private func save(_ configuration: ScoringConfiguration?) {
        do { try model.saveOverride(configuration,leagueID:league.id); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct DecimalEntry: View {
    let title: String
    @Binding var value: Decimal
    @State private var text = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment:.leading) {
            TextField(title,text:$text).keyboardType(.numbersAndPunctuation)
                .onAppear { text = value.exact }
                .onChange(of:text) { _,new in
                    if let number = Decimal.parse(new) { value = number; invalid = false } else { invalid = true }
                }
            if invalid { Text("Invalid decimal; the last valid value \(value.exact) is retained.").font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct RuleEditorView: View {
    @Binding var rule: ScoringRule
    @State private var position = ""
    var body: some View {
        Form {
            Section {
                TextField("Rule label",text:$rule.label)
                TextField("ESPN raw statistic ID",text:$rule.stat).keyboardType(.numberPad)
                Text(StatCatalog.label(rule.stat)).font(.caption).foregroundStyle(.secondary)
                DecimalEntry(title:"Points per unit",value:$rule.multiplier)
                Picker("Calculation",selection:$rule.mode) { ForEach(RuleMode.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    .onChange(of:rule.mode) { _,mode in
                        if mode != .linear && rule.lower == nil { rule.lower = mode == .perWhole ? 10 : 0 }
                        if mode == .range && rule.upper == nil { rule.upper = 99 }
                    }
            }
            if rule.mode != .linear {
                Section {
                    DecimalEntry(title:rule.mode == .perWhole ? "Whole-unit size" : "Lower bound / threshold",value:Binding(get: { rule.lower ?? 0 },set: { rule.lower = $0 }))
                    if rule.mode == .range { DecimalEntry(title:"Inclusive upper bound",value:Binding(get: { rule.upper ?? 0 },set: { rule.upper = $0 })) }
                    Text(rule.mode == .perWhole ? "Whole-unit division truncates toward zero. Other calculations preserve all available decimal precision." : "Threshold awards the configured points once. Range awards them when the raw statistic falls between both inclusive bounds.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Position-specific multipliers") {
                Text("ESPN scoring position IDs: QB 0, RB 2, WR 4, TE 6, D/ST 16, K 17, DE 9, DT 8, LB 10, CB 12, S 13. A position rate replaces the default rate.").font(.caption).foregroundStyle(.secondary)
                ForEach(rule.positionMultipliers.keys.sorted(),id:\.self) { key in
                    HStack {
                        DecimalEntry(title:"Position \(key)",value:Binding(get: { rule.positionMultipliers[key] ?? 0 },set: { rule.positionMultipliers[key] = $0 }))
                        Button("Remove position \(key)",systemImage:"minus.circle",role:.destructive) { rule.positionMultipliers.removeValue(forKey:key) }.labelStyle(.iconOnly)
                    }
                }
                TextField("Position ID",text:$position).keyboardType(.numberPad)
                Button("Add position override") { if !position.isEmpty && position.allSatisfy(\.isNumber) { rule.positionMultipliers[position] = rule.multiplier; position = "" } }
            }
        }.navigationTitle("Scoring rule").navigationBarTitleDisplayMode(.inline)
    }
}
