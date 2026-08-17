import SwiftUI
import AppFeature

struct WatchRootView: View {
    let timer: ActiveTimerController
    let today: TodayController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ActiveTimerScreen(timer: timer)
            TodayScreen(today: today, timer: timer)
        }
        .tabViewStyle(.verticalPage)
        .task { await reloadControllers() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await reloadControllers() }
        }
    }

    private func reloadControllers() async {
        await timer.reload()
        await today.reload()
    }
}
#if DEBUG
#Preview("Watch Root") {
    let timer = PreviewMocks.runningTimer()
    WatchRootView(timer: timer, today: PreviewMocks.today())
        .task { await timer.reload() }
}
#endif
