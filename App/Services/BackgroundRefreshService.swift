import Foundation
@preconcurrency import BackgroundTasks

@MainActor final class BackgroundRefreshService {
    static let shared = BackgroundRefreshService()
    weak var model: AppModel?
    private var registered = false

    func register() {
        guard !registered, !RuntimeEnvironment.isLiveContainer else { return }
        // Register before didFinishLaunching returns. Hosted apps cannot register
        // their own task identifiers, so LiveContainer takes the foreground path.
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier:AppModel.refreshIdentifier,using:.main) { task in
            MainActor.assumeIsolated {
                guard let refresh = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success:false)
                    return
                }
                BackgroundRefreshExecution(task:refresh,model:Self.shared.model).start()
            }
        }
        if !registered { model?.backgroundStatus = "iOS did not register background refresh; foreground refresh remains available" }
    }
}

@MainActor private final class BackgroundRefreshExecution {
    private let task: BGAppRefreshTask
    private let model: AppModel?
    private var work: Task<Void,Never>?
    private var completed = false

    init(task: BGAppRefreshTask, model: AppModel?) {
        self.task = task
        self.model = model
    }
    func start() {
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.finish(success:false) }
        }
        work = Task { @MainActor [self] in
            let success = await model?.refresh() ?? false
            finish(success:success && !Task.isCancelled)
        }
    }
    private func finish(success: Bool) {
        guard !completed else { return }
        completed = true
        work?.cancel()
        work = nil
        task.setTaskCompleted(success:success)
    }
}
