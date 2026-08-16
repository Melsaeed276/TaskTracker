import SwiftUI
import AppData
import AppFeature

@main
struct TaskTrackerWatchApp: App {
    let timerController: ActiveTimerController
    let todayController: TodayController
    private let expiryRefreshLoop: ActiveTimerExpiryRefreshLoop

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let container = try! (
            isUITesting
            ? AppDataModelContainer.makeLocalInMemory()
            : AppDataModelContainer.makeSynced()
        )
        let timerRepository = SwiftDataTimerEventRepository(modelContainer: container)
        let taskRepository = SwiftDataTaskRepository(modelContainer: container)
        timerController = ActiveTimerController(repository: timerRepository)
        todayController = TodayController(repository: taskRepository)
        expiryRefreshLoop = ActiveTimerExpiryRefreshLoop(timer: timerController)
        expiryRefreshLoop.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(timer: timerController, today: todayController)
        }
    }
}
