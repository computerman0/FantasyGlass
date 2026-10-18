import SwiftUI
import SwiftData

@main struct FantasyGlassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    @State private var model: AppModel?
    private let startupError: String?
    init() {
        do {
            _ = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            let container = try ModelContainer(for:CachedLeague.self,CachedObject.self)
            let appModel = AppModel(container:container)
            _model = State(initialValue:appModel)
            BackgroundRefreshService.shared.model = appModel
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model:model)
                    .preferredColorScheme(model.colorScheme)
                    .onOpenURL { model.open($0) }
                    .task(id:phase) {
                        if phase == .active { await model.foregroundLoop() }
                        else { model.scheduleBackgroundRefresh() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for:.remoteTokenChanged)) { _ in Task { await model.syncRemote() } }
                    .onReceive(NotificationCenter.default.publisher(for:.remoteRegistrationFailed)) { note in model.remoteStatus = (note.object as? String) ?? "APNs registration failed" }
            } else {
                ContentUnavailableView("Storage unavailable",systemImage:"externaldrive.badge.exclamationmark",description:Text(startupError ?? "Unable to open the database. Existing data has not been erased."))
            }
        }
    }
}
