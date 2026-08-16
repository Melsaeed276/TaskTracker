import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

enum AppRootTab: Hashable {
    case today
    case pool
    case timer
    case settings
}

struct RootTabView: View {
    let timer: ActiveTimerController
    let today: TodayController
    let pool: PoolController
    var makeTimeLog: ((UUID) -> TaskTimeLogController)?
    @State private var selectedTab: AppRootTab = .today
    /// When set, Today or Pool presents the matching task’s edit sheet.
    @State private var taskIDToPresent: UUID?
    /// Task currently shown in an edit sheet (Today or Pool).
    @State private var presentedTaskID: UUID?

    var body: some View {
        AppTabView(selection: $selectedTab) {
            TodayTabView(
                today: today,
                pool: pool,
                timer: timer,
                taskIDToPresent: $taskIDToPresent,
                presentedTaskID: $presentedTaskID,
                makeTimeLog: makeTimeLog,
                onStartedTimer: { selectedTab = .timer },
                onOpenTimerTab: { selectedTab = .timer }
            )
            .modifier(ActiveTimerBarInset(isVisible: showsActiveTimerBar, bar: { activeTimerBar }))
            .tabItem {
                Label("Today", systemImage: AppSymbols.Navigation.today)
            }
            .tag(AppRootTab.today)

            PoolTabView(
                pool: pool,
                today: today,
                timer: timer,
                taskIDToPresent: $taskIDToPresent,
                presentedTaskID: $presentedTaskID,
                makeTimeLog: makeTimeLog,
                onStartedTimer: { selectedTab = .timer },
                onOpenTimerTab: { selectedTab = .timer }
            )
            .modifier(ActiveTimerBarInset(isVisible: showsActiveTimerBar, bar: { activeTimerBar }))
            .tabItem {
                Label("Pool", systemImage: AppSymbols.Navigation.pool)
            }
            .tag(AppRootTab.pool)

            TimerTabView(
                timer: timer,
                today: today,
                pool: pool,
                onOpenRelatedTask: openRelatedTask
            )
            .tabItem {
                Label("Timer", systemImage: AppSymbols.Navigation.timer)
            }
            .tag(AppRootTab.timer)

            SettingsTabView()
                .modifier(ActiveTimerBarInset(isVisible: showsActiveTimerBar, bar: { activeTimerBar }))
                .tabItem {
                    Label("Settings", systemImage: AppSymbols.Navigation.settings)
                }
                .tag(AppRootTab.settings)
        }
        .animation(.easeInOut(duration: AppDuration.normal), value: showsActiveTimerBar)
        .onOpenURL { url in
            if TaskTrackerDeepLink.isTimer(url) {
                selectedTab = .timer
            }
        }
        .task {
            await today.reload()
            await pool.reload()
            await timer.reload()
            if timer.isActive {
                selectedTab = .timer
            }
        }
    }

    /// App-wide strip while a session is active. Hidden on the Timer tab. While the linked task
    /// sheet is open the sheet hosts the same strip (without Open Task), so this one stays off.
    private var showsActiveTimerBar: Bool {
        guard timer.isActive else { return false }
        if selectedTab == .timer { return false }
        if let related = timer.relatedTaskID, presentedTaskID == related { return false }
        return true
    }

    private var showsOpenTaskOnBar: Bool {
        guard let related = timer.relatedTaskID else { return false }
        return presentedTaskID != related
    }

    private var linkedTask: Task? {
        guard let id = timer.relatedTaskID else { return nil }
        return today.tasks.first(where: { $0.id == id })
            ?? pool.tasks.first(where: { $0.id == id })
    }

    private var activeTimerBar: some View {
        TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
            TaskTimerActionBar(
                countdown: timer.compactLabel(at: context.date) ?? "0:00",
                statusText: timer.isPaused ? "Paused" : "Running",
                isPaused: timer.isPaused,
                onPauseResume: {
                    Swift.Task { @MainActor in
                        if timer.isPaused {
                            await timer.resume()
                        } else {
                            await timer.pause()
                        }
                    }
                },
                onStop: {
                    Swift.Task { @MainActor in
                        await timer.stop()
                    }
                },
                onOpenTimer: { selectedTab = .timer },
                relatedTaskTitle: showsOpenTaskOnBar ? linkedTask?.title : nil,
                onOpenRelatedTask: showsOpenTaskOnBar
                    ? linkedTask.map { task in { openRelatedTask(task.id) } }
                    : nil
            )
        }
    }

    private func openRelatedTask(_ id: UUID) {
        taskIDToPresent = id
        if today.tasks.contains(where: { $0.id == id }) {
            selectedTab = .today
        } else if pool.tasks.contains(where: { $0.id == id }) {
            selectedTab = .pool
        } else {
            selectedTab = .today
            Swift.Task {
                await today.reload()
                await pool.reload()
                if today.tasks.contains(where: { $0.id == id }) {
                    selectedTab = .today
                } else if pool.tasks.contains(where: { $0.id == id }) {
                    selectedTab = .pool
                }
            }
        }
    }
}

/// Pins the active-timer strip into each tab’s content safe area so it sits *above* the tab bar
/// (applying `safeAreaInset` to `TabView` itself draws over the tab bar with sidebar-adaptable style).
private struct ActiveTimerBarInset<Bar: View>: ViewModifier {
    let isVisible: Bool
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: AppSpacing.s) {
                if isVisible {
                    bar()
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.top, AppSpacing.xs)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
}
