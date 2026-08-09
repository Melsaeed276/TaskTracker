import SwiftUI
import AppData
import AppFeature

@main
struct TaskTrackerMacApp: App {
    let controller: ActiveTimerController

    init() {
        let container = try! AppDataModelContainer.makeLocalInMemory()
        let repo = SwiftDataTimerEventRepository(modelContainer: container)
        controller = ActiveTimerController(repository: repo)
    }

    var body: some Scene {
        MenuBarExtra("TaskTracker", systemImage: "timer") {
            TimerPanel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct TimerPanel: View {
    let controller: ActiveTimerController

    var body: some View {
        VStack(spacing: 12) {
            Text(controller.stateDescription)
                .font(.headline)

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
        .frame(minWidth: 200)
        .task { await controller.reload() }
    }
}
