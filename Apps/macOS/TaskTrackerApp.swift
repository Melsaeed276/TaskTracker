import SwiftUI

// Milestone 0 skeleton. The menu-bar experience is built in Milestone 5.
@main
struct TaskTrackerMacApp: App {
    var body: some Scene {
        MenuBarExtra("TaskTracker", systemImage: "timer") {
            Text("TaskTracker")
        }
        .menuBarExtraStyle(.window)
    }
}
