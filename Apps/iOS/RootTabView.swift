import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

enum AppRootTab: Hashable {
    case today
    case pool
    case timer
    case addTask
    case settings
}

struct RootTabView: View {
    let timer: ActiveTimerController
    let today: TodayController
    let pool: PoolController
    var makeTimeLog: ((UUID) -> TaskTimeLogController)?
    @State private var selectedTab: AppRootTab = .today
    @State private var lastContentTab: AppRootTab = .today
    @State private var isQuickTaskEntryPresented = false
    @State private var quickTaskDraft = ""
    /// When set, Today or Pool presents the matching task’s edit sheet.
    @State private var taskIDToPresent: UUID?
    /// Task currently shown in an edit sheet (Today or Pool).
    @State private var presentedTaskID: UUID?

    @ViewBuilder
    var body: some View {
        if #available(iOS 18, *) {
            nativeSearchTabBody
        } else {
            legacyTabBody
        }
    }

    @available(iOS 18, *)
    private var nativeSearchTabBody: some View {
        nativeSearchTabView
            .onOpenURL { url in
                if TaskTrackerDeepLink.isTimer(url) {
                    selectedTab = .timer
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                if newValue != .addTask {
                    lastContentTab = newValue
                }
            }
            .task { await initialLoad() }
    }

    private var legacyTabBody: some View {
        AppTabView(selection: $selectedTab) {
            todayTabContent
            .tabItem {
                Label("Today", systemImage: AppSymbols.Navigation.today)
            }
            .tag(AppRootTab.today)

            poolTabContent
            .tabItem {
                Label("Pool", systemImage: AppSymbols.Navigation.pool)
            }
            .tag(AppRootTab.pool)

            timerTabContent
            .tabItem {
                Label("Timer", systemImage: AppSymbols.Navigation.timer)
            }
            .tag(AppRootTab.timer)

            settingsTabContent
            .tabItem {
                Label("Settings", systemImage: AppSymbols.Navigation.settings)
            }
            .tag(AppRootTab.settings)
        }
        .overlay(alignment: .bottom) {
            if isQuickTaskEntryPresented {
                quickTaskEntryOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isQuickTaskEntryPresented {
                quickTaskButton
                    .padding(.trailing, AppSpacing.m)
                    .padding(.bottom, AppSpacing.l)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: AppDuration.normal), value: isQuickTaskEntryPresented)
        .onOpenURL { url in
            if TaskTrackerDeepLink.isTimer(url) {
                selectedTab = .timer
            }
        }
        .onChange(of: selectedTab) { _, _ in
            isQuickTaskEntryPresented = false
            lastContentTab = selectedTab
        }
        .task { await initialLoad() }
    }

    @available(iOS 18, *)
    @ViewBuilder
    private var nativeSearchTabView: some View {
        let view = TabView(selection: $selectedTab) {
            Tab("Today", systemImage: AppSymbols.Navigation.today, value: AppRootTab.today) {
                todayTabContent
            }
            Tab("Pool", systemImage: AppSymbols.Navigation.pool, value: AppRootTab.pool) {
                poolTabContent
            }
            Tab("Timer", systemImage: AppSymbols.Navigation.timer, value: AppRootTab.timer) {
                timerTabContent
            }
            Tab(value: AppRootTab.addTask, role: .search) {
                quickTaskSearchContent
            } label: {
                Label {
                    Text("Add")
                } icon: {
                    AddTaskSymbolIcon(isActive: selectedTab == .addTask)
                }
            }
            Tab("Settings", systemImage: AppSymbols.Navigation.settings, value: AppRootTab.settings) {
                settingsTabContent
            }
        }
        .tabViewStyle(.sidebarAdaptable)

        if #available(iOS 26, *) {
            view
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewSearchActivation(.searchTabSelection)
        } else {
            view
        }
    }

    private var todayTabContent: some View {
        TodayTabView(
            today: today,
            pool: pool,
            timer: timer,
            taskIDToPresent: $taskIDToPresent,
            presentedTaskID: $presentedTaskID,
            makeTimeLog: makeTimeLog,
            onStartedTimer: { selectedTab = .timer },
            onOpenTimerTab: { selectedTab = .timer },
            onOpenPoolTab: { selectedTab = .pool }
        )
    }

    private var poolTabContent: some View {
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
    }

    private var timerTabContent: some View {
        TimerTabView(
            timer: timer,
            today: today,
            pool: pool,
            onOpenRelatedTask: openRelatedTask
        )
    }

    private var settingsTabContent: some View {
        SettingsTabView()
    }

    private var quickTaskSearchContent: some View {
        NavigationStack {
            List {
                if quickTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        VStack(spacing: AppSpacing.s) {
                            AddTaskSymbolIcon(isActive: selectedTab == .addTask)
                                .font(.largeTitle)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)

                            Text("Type a task title, then press Search to add it.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if matchingActiveTasks.isEmpty {
                    Section {
                        Button {
                            submitQuickTask(quickTaskDraft)
                        } label: {
                            Label("Add \"\(quickTaskDraft)\"", systemImage: AppSymbols.Tasks.add)
                        }
                    }
                } else {
                    Section("Existing tasks") {
                        ForEach(matchingActiveTasks.prefix(8)) { task in
                            Button {
                                selectQuickTaskSuggestion(task)
                            } label: {
                                Label(task.title, systemImage: AppSymbols.Navigation.taskHub)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Task")
        }
        .searchable(text: $quickTaskDraft, prompt: "Add or search task")
        .onSubmit(of: .search) {
            submitQuickTask(quickTaskDraft)
        }
    }

    private var quickTaskButton: some View {
        Button {
            isQuickTaskEntryPresented = true
        } label: {
            Image(systemName: AppSymbols.Navigation.addTask)
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 64, height: 64)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.secondary.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Task")
        .accessibilityIdentifier("root.addTaskButton")
    }

    private var quickTaskEntryOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { dismissQuickTaskEntry() }

            TaskQuickEntryView(
                placeholder: "Add or search task",
                draft: $quickTaskDraft,
                suggestions: matchingActiveTasks,
                textFieldIdentifier: "root.quickTaskField",
                focusOnAppear: true,
                onSubmit: submitQuickTask,
                onSelectSuggestion: selectQuickTaskSuggestion
            )
            .padding(.bottom, AppSpacing.s)
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

    private var matchingActiveTasks: [Task] {
        let query = normalized(quickTaskDraft)
        guard !query.isEmpty else { return [] }
        return pool.tasks.filter {
            !$0.isCompleted && normalized($0.title).contains(query)
        }
    }

    private func submitQuickTask(_ title: String) {
        let targetTab = quickEntrySourceTab
        dismissQuickTaskEntry()
        Swift.Task { @MainActor in
            if targetTab == .today {
                await today.quickAdd(title: title)
                await pool.reload()
            } else {
                await pool.quickAdd(title: title)
                await today.reload()
                await pool.reload()
            }
            selectedTab = targetTab
        }
    }

    private func selectQuickTaskSuggestion(_ task: Task) {
        let targetTab = quickEntrySourceTab
        dismissQuickTaskEntry()
        if targetTab == .today {
            Swift.Task { @MainActor in
                await today.scheduleForToday(task)
                await today.reload()
                await pool.reload()
                selectedTab = .today
            }
        } else {
            selectedTab = .pool
            taskIDToPresent = task.id
        }
    }

    private func dismissQuickTaskEntry() {
        quickTaskDraft = ""
        isQuickTaskEntryPresented = false
    }

    private func initialLoad() async {
        await today.reload()
        await pool.reload()
        await timer.reload()
        if timer.isActive {
            selectedTab = .timer
        }
    }

    private var quickEntrySourceTab: AppRootTab {
        selectedTab == .addTask ? lastContentTab : selectedTab
    }

    private func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}

/// Pins the active-timer strip into each tab’s content safe area so it sits *above* the tab bar
/// (applying `safeAreaInset` to `TabView` itself draws over the tab bar with sidebar-adaptable style).
private struct AddTaskSymbolIcon: View {
    let isActive: Bool

    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: AppSymbols.Navigation.addTask)
                .symbolVariant(.none)
                .symbolEffect(.drawOn, options: .nonRepeating, isActive: isActive)
        } else {
            Image(systemName: AppSymbols.Navigation.addTask)
                .symbolVariant(.none)
        }
    }
}
