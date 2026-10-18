import SwiftUI
import FantasyCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var setup = false
    @State private var permissionStatus = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Connections") {
                    Button("Open setup assistant",systemImage:"wand.and.stars") { setup = true }
                    ForEach(model.preferences.accountAliases,id:\.self) { account in NavigationLink("ESPN · \(account)") { ESPNAccountView(model:model,initialAlias:account) } }
                    NavigationLink { ESPNAccountView(model:model,initialAlias:"") } label: { Label("Add ESPN account",systemImage:"person.badge.plus") }
                    NavigationLink { SportsSetupView(model:model) } label: { Label("Sports data providers",systemImage:"waveform.path.ecg") }
                    NavigationLink { BackendSetupView(model:model) } label: { Label("APNs and backend",systemImage:"antenna.radiowaves.left.and.right") }
                }
                Section("Live Activities") {
                    Toggle("Enable Live Activities",isOn:$model.preferences.liveActivitiesEnabled)
                        .onChange(of:model.preferences.liveActivitiesEnabled) { _,enabled in if !enabled { Task { await model.endTracking() } } }
                    Picker("Default matchup",selection:$model.preferences.defaultMatchup) {
                        Text("Choose when tracking").tag("")
                        ForEach(model.leagues) { Text("\($0.snapshot.name) · \($0.team?.name ?? "")").tag($0.id) }
                    }
                    Text("An activity lasts at most eight hours in Dynamic Island. Reopen FantasyGlass to pin another session. Tap the activity to open its exact matchup.").font(.caption).foregroundStyle(.secondary)
                    Text(model.preferences.remoteEnabled ? model.remoteStatus : "Local updates only. Refreshes are not guaranteed while suspended.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Notifications") {
                    Button("Request notification permission") {
                        Task {
                            do { permissionStatus = try await model.notifications.requestAuthorization(remote:model.preferences.remoteEnabled && AppModel.supportsPushBuild) ? "Notifications allowed." : "Notifications declined. Enable them in iOS Settings." }
                            catch { permissionStatus = error.localizedDescription }
                        }
                    }
                    if !permissionStatus.isEmpty { Text(permissionStatus).font(.caption) }
                    ForEach(AlertKind.allCases,id:\.self) { kind in
                        Toggle(kind.title,isOn:Binding(get: { model.preferences.alerts.enabled.contains(kind) },set: { enabled in
                            if enabled { model.preferences.alerts.enabled.insert(kind) } else { model.preferences.alerts.enabled.remove(kind) }
                        }))
                    }
                    Text("Set individual point thresholds on Player pages. Without the APNs backend, alerts can only be detected when iOS lets this app run. Aggregate stat changes can be corrected; touchdown alerts are not play-by-play guarantees.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Refresh and appearance") {
                    Picker("Foreground active-game interval",selection:$model.preferences.refreshSeconds) {
                        Text("30 seconds").tag(30.0); Text("60 seconds").tag(60.0); Text("2 minutes").tag(120.0)
                    }
                    Text("Idle requests back off to 15 minutes. Provider rate limits take precedence. Background refresh timing is chosen by iOS.").font(.caption).foregroundStyle(.secondary)
                    Text(model.backgroundStatus).font(.caption).foregroundStyle(.secondary)
                    Picker("Appearance",selection:$model.preferences.appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                }
                Section("About the data") {
                    Text("FantasyGlass 1.0 · Native iOS 26\nESPN is an unofficial read-only provider. Local rule edits do not change ESPN. All score precision is preserved; values are not silently rounded. Win probability is unavailable without a calibrated model.").font(.footnote).foregroundStyle(.secondary)
                    Text("Cached data stays on this device. Secrets use Keychain and are excluded from device migration. No analytics SDK is included.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
                .sheet(isPresented:$setup) { SetupAssistantView(model:model) }
                .onDisappear { Task { await model.syncRemote() } }
        }
    }
}
