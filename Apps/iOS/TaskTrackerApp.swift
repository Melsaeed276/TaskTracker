import SwiftUI
import AppData
import AppDesign
import AppFeature

@main
struct TaskTrackerIOSApp: App {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .auto
    let timerController: ActiveTimerController
    let todayController: TodayController
    let poolController: PoolController
    private let timerEventRepository: SwiftDataTimerEventRepository
    private let timeLogRepository: SwiftDataTaskTimeLogRepository
    private let expiryRefreshLoop: ActiveTimerExpiryRefreshLoop
    private let remoteChangeCoordinator: RemoteChangeCoordinator

    init() {
        LanguagePreference.shared.apply()
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let container = try! (
            isUITesting
            ? AppDataModelContainer.makeLocalInMemory()
            : AppDataModelContainer.makeSynced()
        )
        let timerRepo = SwiftDataTimerEventRepository(modelContainer: container)
        let taskRepo = SwiftDataTaskRepository(modelContainer: container)
        let timeLogRepo = SwiftDataTaskTimeLogRepository(modelContainer: container)
        timerEventRepository = timerRepo
        timeLogRepository = timeLogRepo
        timerController = ActiveTimerController(
            repository: timerRepo,
            expiryNotifier: UserNotificationsTimerExpiryNotifier(),
            liveActivity: ActivityKitTimerLiveActivityController()
        )
        todayController = TodayController(repository: taskRepo)
        poolController = PoolController(repository: taskRepo)
        expiryRefreshLoop = ActiveTimerExpiryRefreshLoop(timer: timerController)
        expiryRefreshLoop.start()
        remoteChangeCoordinator = RemoteChangeCoordinator(
            timer: timerController,
            today: todayController,
            pool: poolController
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                timer: timerController,
                today: todayController,
                pool: poolController,
                makeTimeLog: { taskID in
                    TaskTimeLogController(
                        taskID: taskID,
                        timerEvents: timerEventRepository,
                        timeLog: timeLogRepository
                    )
                }
            )
            .preferredColorScheme(appearance.colorScheme)
        }
    }
}

@MainActor
private final class RemoteChangeCoordinator {
    init(timer: ActiveTimerController, today: TodayController, pool: PoolController) {
        NotificationCenter.default.addObserver(
            forName: AppDataModelContainer.remoteChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await timer.reload()
                await today.reload()
                await pool.reload()
            }
        }
    }
}
