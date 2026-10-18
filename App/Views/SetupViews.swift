import SwiftUI
import FantasyCore

struct SetupAssistantView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading,spacing:16) {
                        Image(systemName:"football.fill").font(.system(size:48)).foregroundStyle(.cyan).padding().glassEffect()
                        Text("Welcome to\nFantasyGlass").font(.largeTitle.bold())
                        Text("Your leagues, your scoring, one native home for game day.").font(.title3).foregroundStyle(.secondary)
                    }.padding(.vertical,14)
                }
                Section("1 · Connect a fantasy league") {
                    Text("ESPN is required for league import. Public leagues need a league ID and season. Private leagues also need your existing ESPN session cookies. No ESPN password is collected.")
                    NavigationLink { LeagueConnectForm(model:model,onConnected: { dismiss() }) } label: { Label("Connect ESPN league",systemImage:"trophy") }
                    Link("Open ESPN Fantasy Football",destination:URL(string:"https://www.espn.com/fantasy/football/")!)
                }
                Section("2 · Choose live statistics") {
                    Text("ESPN's unofficial fantasy data is the default, with no API subscription. Availability and latency are not guaranteed. SportsDataIO is optional and requires a suitable NFL data plan; a free trial may contain scrambled statistics.")
                    NavigationLink { SportsSetupView(model:model) } label: { Label("Sports data setup",systemImage:"waveform.path.ecg") }
                }
                Section("3 · Choose background updates") {
                    Text("Local Live Activities work without a server while the app can run. For updates and alerts while suspended, configure the optional APNs backend and a paid Apple Developer provisioning profile. iOS controls delivery and activity lifetime.")
                    NavigationLink { BackendSetupView(model:model) } label: { Label("APNs and backend setup",systemImage:"antenna.radiowaves.left.and.right") }
                }
                Section("Your credentials") {
                    Label("Stored in the iOS Keychain",systemImage:"key.fill")
                    Text("Secrets stay on this device unless you explicitly enable the optional backend, which needs encrypted server copies to retrieve private league data while your phone is asleep.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Setup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { model.preferences.onboardingComplete = true; dismiss() } } }
        }
    }
}

struct LeagueConnectView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LeagueConnectForm(model:model,onConnected: { dismiss() })
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
struct LeagueConnectForm: View {
    let model: AppModel
    let onConnected: () -> Void
    @State private var leagueID = ""
    @State private var season = String(Calendar.current.component(.year,from:.now) - (Calendar.current.component(.month,from:.now) < 4 ? 1 : 0))
    @State private var account = "default"
    @State private var snapshot: LeagueSnapshot?
    @State private var selected: Set<Int> = []
    @State private var testing = false
    @State private var status: String?
    var body: some View {
        Form {
            Section("ESPN Fantasy Football") {
                Text("Unofficial, read-only integration. ESPN may change or restrict these endpoints. Account-wide league discovery is not a verified supported capability.").font(.footnote).foregroundStyle(.secondary)
                TextField("League ID",text:$leagueID).keyboardType(.numberPad)
                TextField("Season",text:$season).keyboardType(.numberPad)
                Picker("Account",selection:$account) { ForEach(model.preferences.accountAliases,id:\.self) { Text($0).tag($0) } }
                Text("Find leagueId in the URL when viewing your league on ESPN. A league ID is not a password.").font(.caption).foregroundStyle(.secondary)
                NavigationLink { ESPNAccountView(model:model,initialAlias:account) } label: { Label("Private league credentials",systemImage:"key") }
                Link("Open ESPN Fantasy Football",destination:URL(string:"https://www.espn.com/fantasy/football/")!)
            }
            Section {
                Button {
                    testing = true; status = nil; snapshot = nil
                    Task {
                        defer { testing = false }
                        do {
                            guard let year = Int(season) else { throw ProviderError.invalidInput("Enter a four-digit season.") }
                            let result = try await model.inspectLeague(id:leagueID,season:year,account:account)
                            snapshot = result
                            let owner = try model.credentials(account:account)?.swid
                            selected = Set(result.teams.filter { team in team.owners.contains { $0.caseInsensitiveCompare(owner ?? "") == .orderedSame } }.map(\.id))
                            status = "Connection verified: \(result.name), \(result.teams.count) teams. Select the team or teams you own."
                        } catch { status = error.localizedDescription }
                    }
                } label: { if testing { ProgressView("Testing connection…") } else { Label("Test Connection",systemImage:"checkmark.shield") } }
                .disabled(testing || leagueID.isEmpty).buttonStyle(.glass)
                if let status { Text(status).font(.footnote).textSelection(.enabled) }
                Text("Usage and quota: ESPN does not publish a supported API quota. FantasyGlass backs off on HTTP 429 and avoids frequent idle requests.").font(.caption).foregroundStyle(.secondary)
            }
            if let snapshot {
                Section("Choose your teams") {
                    ForEach(snapshot.teams) { team in
                        Toggle(isOn:Binding(get: { selected.contains(team.id) },set: { enabled in if enabled { selected.insert(team.id) } else { selected.remove(team.id) } })) {
                            VStack(alignment:.leading) { Text(team.name); Text(team.record).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Connect selected teams") {
                        do { try model.connect(snapshot:snapshot,teamIDs:selected,account:account); onConnected(); Task { await model.refresh() } }
                        catch { status = error.localizedDescription }
                    }.disabled(selected.isEmpty).buttonStyle(.glassProminent)
                }
            }
        }.navigationTitle("Connect ESPN").navigationBarTitleDisplayMode(.inline)
            .onChange(of:leagueID) { snapshot = nil }
            .onChange(of:season) { snapshot = nil }
            .onChange(of:account) { snapshot = nil }
    }
}

struct ESPNAccountView: View {
    let model: AppModel
    var initialAlias = "default"
    @State private var alias = ""
    @State private var s2 = ""
    @State private var swid = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section("Existing ESPN session") {
                Text("Public leagues need no cookies. For a private league, sign in to ESPN yourself in a desktop browser. Open Developer Tools → Application/Storage → Cookies for espn.com. Copy your own espn_s2 and SWID values into these secure fields. Browser labels vary.")
                Text("This is an unsupported session-cookie method, not OAuth. These cookies may grant account access and can expire. Never share them in chat, source code, screenshots or logs. FantasyGlass never asks for your ESPN password.").font(.footnote).foregroundStyle(.orange)
                Link("ESPN Fantasy sign-in",destination:URL(string:"https://www.espn.com/fantasy/football/")!)
            }
            Section {
                TextField("Local account alias",text:$alias).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("espn_s2",text:$s2).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                SecureField("SWID",text:$swid).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Button("Save securely to Keychain") {
                    do { try model.saveESPN(account:alias,s2:s2,swid:swid); s2 = ""; swid = ""; status = "Saved. Test access with your league ID in Connect ESPN." }
                    catch { status = error.localizedDescription }
                }.buttonStyle(.glass)
                Button("Remove saved credentials",role:.destructive) {
                    do { try model.clearESPN(account:alias); status = "Removed from this device. Private leagues need new credentials to refresh." }
                    catch { status = error.localizedDescription }
                }
                if !status.isEmpty { Text(status).font(.footnote) }
            }
            Section { Text("Connection verification is performed against a specific league, because there is no verified supported ESPN account-authentication endpoint. Use Test Connection in Connect ESPN after saving.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("ESPN account").navigationBarTitleDisplayMode(.inline)
            .onAppear { alias = initialAlias; status = (try? model.credentials(account:initialAlias)) != nil ? "Credentials saved in Keychain; league access has not been tested here." : "No private credentials saved for this alias." }
    }
}

struct SportsSetupView: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    @State private var testing = false
    @State private var status = "Not tested"
    @State private var players: [ExternalPlayerStats] = []
    var body: some View {
        Form {
            Section("Statistics provider") {
                Picker("Use",selection:$model.preferences.sportsProvider) {
                    Text("ESPN unofficial · no subscription").tag("espn")
                    Text("SportsDataIO · NFL plan required").tag("sportsdata")
                }
                Text("ESPN imports raw statistics and projections when supplied with the league. SportsDataIO can replace supported raw stat lines. Each player's actual source remains visible.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("SportsDataIO setup") {
                Text("1. Register with SportsDataIO.\n2. Request NFL player game statistics and confirm live/historical entitlements and pricing.\n3. Copy the API key from your account's API access page.\n4. Save it here and test access.\n5. Confirm accurate production data, then map player IDs on each Player page.")
                Link("Register / free trial",destination:URL(string:"https://sportsdata.io/cart/free-trial")!)
                Link("Official NFL API documentation",destination:URL(string:"https://sportsdata.io/developers/api-documentation/nfl")!)
                Link("Field dictionary and scrambled-data flags",destination:URL(string:"https://sportsdata.io/developers/data-dictionary/nfl")!)
                Text("A trial can return scrambled data even when HTTP access succeeds. Do not use trial statistics to judge your fantasy matchup. Production prices and quotas are plan-specific; this app does not promise a free live feed.").font(.footnote).foregroundStyle(.orange)
                SecureField("API key",text:$apiKey).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Button("Save API key to Keychain") {
                    do { guard !apiKey.isEmpty else { throw ProviderError.invalidInput("Enter your API key.") }; try model.keychain.write(apiKey,account:"sportsdata.key"); apiKey = ""; status = "Key saved; connection not yet verified." }
                    catch { status = error.localizedDescription }
                }
                Toggle("My plan provides licensed, accurate production statistics",isOn:$model.preferences.accurateFeedConfirmed)
            }
            Section("Connection") {
                Button {
                    testing = true
                    Task {
                        defer { testing = false }
                        do {
                            let key = apiKey.isEmpty ? try model.keychain.read("sportsdata.key") ?? "" : apiKey
                            let league = model.leagues.first
                            players = try await model.sportsData.playerStats(season:league?.snapshot.season ?? Calendar.current.component(.year,from:.now),week:league?.snapshot.week ?? 1,apiKey:key)
                            status = "HTTP access and response verified: \(players.count) player rows. Accuracy and live entitlement must still be confirmed with SportsDataIO. Quota is not exposed by this response."
                        } catch { status = error.localizedDescription }
                    }
                } label: { if testing { ProgressView("Testing…") } else { Text("Test Connection") } }.disabled(testing)
                Text(status).font(.footnote).textSelection(.enabled)
                if !players.isEmpty {
                    DisclosureGroup("Player IDs for mapping") {
                        ForEach(players.prefix(200)) { player in LabeledContent("\(player.name) · \(player.team)",value:player.id).font(.caption).textSelection(.enabled) }
                    }
                }
            }
            Section("Other providers") {
                Link("Sportradar NFL documentation",destination:URL(string:"https://developer.sportradar.com/football/docs/nfl-ig-api-basics")!)
                Text("Sportradar requires a server-side key and a suitable contract. A working Sportradar, Yahoo, or Sleeper adapter is not included in this version.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Sports data").navigationBarTitleDisplayMode(.inline)
    }
}

struct BackendSetupView: View {
    @Bindable var model: AppModel
    @State private var token = ""
    @State private var consent = false
    @State private var busy = false
    @State private var status = "Not tested"
    var body: some View {
        Form {
            Section("Optional remote updates") {
                Text("The on-device app is usable without a server. Reliable background score polling requires an always-running backend; APNs sends Live Activity updates and notification alerts. Apple controls final delivery and limits each activity's lifetime.")
                Text("1. Use a paid Apple Developer account.\n2. Register app and widget bundle IDs; enable Push Notifications for the app.\n3. Create an APNs signing key and matching profiles.\n4. Deploy the included Backend with HTTPS, encryption and owner tokens.\n5. Install the Push build.\n6. Enter its URL/token, test it and enable synchronization.").font(.footnote)
                Link("Apple membership and capabilities",destination:URL(string:"https://developer.apple.com/support/compare-memberships/")!)
                Link("Apple Live Activity push guide",destination:URL(string:"https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications")!)
                Text(AppModel.supportsPushBuild ? "This build includes the APNs entitlement; matching signing is still required." : "This build is configured for local updates. Rebuild with the Push scheme and paid provisioning to enable APNs.").font(.footnote).foregroundStyle(.orange)
            }
            Section("Your backend") {
                TextField("https://your-backend.example",text:$model.preferences.backendURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.preferences.remoteEnabled)
                SecureField("Backend owner token",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().disabled(model.preferences.remoteEnabled)
                Button("Save token in Keychain") {
                    do { guard token.count >= 32 else { throw ProviderError.invalidInput("Use a random owner token of at least 32 characters.") }; try model.keychain.write(token,account:"backend.token"); token = ""; status = "Token saved." }
                    catch { status = error.localizedDescription }
                }.disabled(model.preferences.remoteEnabled)
                Button("Test Connection") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            let secret = token.isEmpty ? try model.keychain.read("backend.token") ?? "" : token
                            let data = try await model.remote.request(baseURL:model.preferences.backendURL,token:secret,path:"v1/status")
                            let result = try JSONDecoder().decode(JSONValue.self,from:data)
                            status = "Backend verified. APNs configured: \(result["apnsConfigured"].bool ? "yes" : "no"). Environment: \(result["environment"].string ?? "unknown"). This does not prove delivery to your iPhone."
                        } catch { status = error.localizedDescription }
                    }
                }.disabled(busy)
                if busy { ProgressView() }
                Text(status).font(.footnote).textSelection(.enabled)
            }
            Section("Enable synchronization") {
                Toggle("Allow this backend to store encrypted ESPN cookies, selected API keys, scoring rules and push tokens",isOn:$consent)
                if model.preferences.remoteEnabled {
                    Button("Disable and delete server subscriptions",role:.destructive) {
                        busy = true
                        Task { defer { busy = false }; do { try await model.disableRemote(); status = "Remote subscriptions removed." } catch { status = "Could not remove server subscriptions: \(error.localizedDescription). Remote mode remains enabled. You can also stop the server manually." } }
                    }.disabled(busy)
                } else {
                    Button("Enable remote updates") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                let secret = try model.keychain.read("backend.token") ?? ""
                                let data = try await model.remote.request(baseURL:model.preferences.backendURL,token:secret,path:"v1/status")
                                let server = try JSONDecoder().decode(JSONValue.self,from:data)
                                guard server["apnsConfigured"].bool else { throw ProviderError.invalidInput("Configure APNs on your backend before enabling remote updates.") }
                                model.preferences.remoteEnabled = true
                                _ = try await model.notifications.requestAuthorization(remote:true)
                                await model.syncRemote()
                                status = "Remote mode enabled. Re-pin the matchup to request a Live Activity push token."
                            } catch { status = error.localizedDescription }
                        }
                    }.disabled(!consent || busy || !AppModel.supportsPushBuild).buttonStyle(.glassProminent)
                }
                Text(model.remoteStatus).font(.caption).foregroundStyle(.secondary)
                Text("Disable synchronization before changing server addresses or tokens, so the old server's subscriptions can be deleted. Polling cannot continue on hosting plans that sleep. No hosting cost or APNs delivery rate is guaranteed.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Background updates").navigationBarTitleDisplayMode(.inline)
    }
}
