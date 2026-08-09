import SwiftUI
import AppData
import AppFeature

@main
struct TaskTrackerIOSApp: App {
    let controller: ActiveTimerController

    init() {
        let container = try! AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        controller = ActiveTimerController(repository: repo)
    }

    var body: some Scene {
        WindowGroup {
            TimerView(controller: controller)
        }
    }
}

private struct TimerView: View {
    let controller: ActiveTimerController

    var body: some View {
        VStack(spacing: 20) {
            Text(controller.stateDescription)
                .font(.largeTitle)

            Button("Start") {
                Task { await controller.start() }
            }

            Button(controller.isPaused ? "Resume" : "Pause") {
                Task {
                    if controller.isPaused {
                        await controller.resume()
                    } else {
                        await controller.pause()
                    }
                }
            }

            Button("Stop") {
                Task { await controller.stop() }
            }
        }
        .padding()
        .task { await controller.reload() }
    }
}
