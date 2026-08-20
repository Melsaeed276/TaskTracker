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
    /// Triggers the draw-on animation each time the Add tab opens.
    @State private var addTabAnimationID = 0
    /// When set, Today or Pool presents the matching task's edit sheet.
    @State private var taskIDToPresent: UUID?
    /// Task currently shown in an edit sheet (Today or Pool).
    @State private var presentedTaskID: UUID?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    var body: some View {
        if #available(iOS 18, *) {
            nativeSearchTabBody
        } else if horizontalSizeClass == .regular {
            iPadSplitBody
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
                if newValue == .addTask {
                    addTabAnimationID += 1
                } else {
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

    private var iPadSplitBody: some View {
        NavigationSplitView {
            List {
                Section("Tasks") {
                    Button {
                        selectedTab = .today
                    } label: {
                        Label("Today", systemImage: AppSymbols.Navigation.today)
                            .foregroundStyle(selectedTab == .today ? Color.accentColor : Color.primary)
                    }
                    Button {
                        selectedTab = .pool
                    } label: {
                        Label("Pool", systemImage: AppSymbols.Navigation.pool)
                            .foregroundStyle(selectedTab == .pool ? Color.accentColor : Color.primary)
                    }
                }
                Section("Focus") {
                    Button {
                        selectedTab = .timer
                    } label: {
                        Label("Timer", systemImage: AppSymbols.Navigation.timer)
                            .foregroundStyle(selectedTab == .timer ? Color.accentColor : Color.primary)
                    }
                }
            }
            .navigationTitle("Task Tracker")
        } detail: {
            Group {
                switch selectedTab {
                case .today:
                    todayTabContent
                case .pool:
                    poolTabContent
                case .timer:
                    timerTabContent
                case .addTask:
                    quickTaskSearchContent
                case .settings:
                    settingsTabContent
                }
            }
            .overlay(alignment: .bottom) {
                if isQuickTaskEntryPresented {
                    quickTaskEntryOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isQuickTaskEntryPresented && selectedTab != .settings {
                    quickTaskButton
                        .padding(.trailing, AppSpacing.m)
                        .padding(.bottom, AppSpacing.l)
                        .transition(.scale.combined(with: .opacity))
                }
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
                Label("Add", systemImage: AppSymbols.Navigation.addTask)
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
            if quickTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AddTaskEmptyState(animationTrigger: addTabAnimationID)
            } else {
                List {
                    if matchingActiveTasks.isEmpty {
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
        .accessibilityLabel(String(localized: "Add Task"))
        .accessibilityIdentifier("root.addTaskButton")
    }

    private var quickTaskEntryOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { dismissQuickTaskEntry() }

            TaskQuickEntryView(
                placeholder: String(localized: "Add or search task"),
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
/// Draw-on entrance symbol for the Add/search tab: a plus inside a rounded rectangle that
/// strokes itself on when the page opens and then stays fully drawn.
///
/// This is a path animation rather than `.symbolEffect(.drawOn)` on purpose: the iOS 26
/// DrawOn symbol effect holds the symbol *undrawn* once a non-repeating run finishes (and
/// renders nothing at all on the simulator), so the icon vanished right after its animation.
private struct AddTaskDrawOnIcon: View {
    let trigger: Int
    @State private var progress: CGFloat = 0
    @State private var replayTask: Swift.Task<Void, Never>?

    var body: some View {
        plusInRectangle
            .trim(from: 0, to: progress)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 18)
            .accessibilityHidden(true)
            .onChange(of: trigger) { _, _ in
                playAnimation()
            }
            .onAppear {
                playAnimation()
            }
    }

    private func playAnimation() {
        replayTask?.cancel()
        progress = 0
        withAnimation(.easeInOut(duration: 0.5)) {
            progress = 1
        }
        replayTask = Swift.Task { @MainActor in
            try? await Swift.Task.sleep(for: .seconds(4))
            guard !Swift.Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                progress = 0
            }
            try? await Swift.Task.sleep(for: .seconds(0.15))
            guard !Swift.Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                progress = 1
            }
        }
    }

    /// `plus.rectangle`-matching glyph; rect perimeter first, then the plus, so the trim
    /// draws the outline before the plus (matching the SF Symbols DrawOn motion).
    private var plusInRectangle: Path {
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 1, y: 1, width: 20, height: 16),
            cornerSize: CGSize(width: 3, height: 3)
        )
        path.move(to: CGPoint(x: 11, y: 5))
        path.addLine(to: CGPoint(x: 11, y: 13))
        path.move(to: CGPoint(x: 7, y: 9))
        path.addLine(to: CGPoint(x: 15, y: 9))
        return path
    }
}

/// Empty state for the Add/search tab. The symbol replays its draw-on motion each time the
/// page opens and stays visible afterwards. Centered against the full screen:
/// `.ignoresSafeArea(.keyboard)` stops the auto-opened search keyboard from shrinking the
/// layout area and pushing the content to the top.
private struct AddTaskEmptyState: View {
    let animationTrigger: Int

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            AddTaskDrawOnIcon(trigger: animationTrigger)

            Text("Type a task title, then tap Add to create it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .padding(AppSpacing.xl)
        .navigationTitle("Add Task")
    }
}
