import SwiftUI
import AppKit
import AppData
import AppDesign
import AppFeature
import TaskDomain

@main
struct TaskTrackerMacApp: App {
    static let taskHubWindowID = "task-hub"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .auto

    let timerController: ActiveTimerController
    let todayController: TodayController
    let poolController: PoolController
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
        timerController = ActiveTimerController(
            repository: timerRepo,
            expiryNotifier: UserNotificationsTimerExpiryNotifier()
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
        MenuBarExtra {
            MenuBarPanel(timer: timerController, today: todayController)
        } label: {
            MenuBarStatusLabel(timer: timerController)
        }
        .menuBarExtraStyle(.window)

        Window("Tasks", id: Self.taskHubWindowID) {
            TaskHubView(
                today: todayController,
                pool: poolController,
                timer: timerController
            )
            .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 880, height: 560)

        Settings {
            PreferencesView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

/// Promotes the LSUIElement menu-bar app to a regular foreground app during UI tests so XCUITest
/// can activate it (accessory apps stay "Running Background", which XCUITest refuses to drive).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        // Must happen before launch finishes for the activation policy to take effect.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// Bridges `AppData`'s CloudKit remote-change notification to the live controllers. Lives at the
/// app layer, not in `AppFeature` or `AppData`, since it's the only place both are already imported
/// (see AGENTS.md dependency rules — `AppData` must not know about `AppFeature`'s controllers).
@MainActor
private final class RemoteChangeCoordinator {
    // No deinit/removeObserver: this coordinator lives for the app's entire process lifetime,
    // owned by `@main App`'s stored properties, which SwiftUI never deallocates — a nonisolated
    // deinit couldn't safely touch the (non-Sendable) observer token under Swift 6 strict
    // concurrency anyway (see AGENTS.md: no `@unchecked Sendable` workarounds for a real issue).
    init(timer: ActiveTimerController, today: TodayController, pool: PoolController) {
        NotificationCenter.default.addObserver(
            forName: AppDataModelContainer.remoteChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Swift.Task { @MainActor in
                await timer.reload()
                await today.reload()
                await pool.reload()
            }
        }
    }
}

private struct MenuBarStatusLabel: View {
    let timer: ActiveTimerController

    var body: some View {
        // macOS has no ActivityKit Live Activities — the status-item countdown is the glance surface
        // (plan §21 / ROADMAP: icon when idle, monospaced remaining when active).
        TimelineView(.periodic(from: TimerUI.timelineAnchor, by: 1)) { context in
            Group {
                if let label = timer.compactLabel(at: context.date) {
                    Text(label)
                        .font(.body.monospacedDigit().weight(.semibold))
                } else {
                    Image(nsImage: MenuBarStatusIcon.templateImage)
                        .renderingMode(.template)
                }
            }
            .accessibilityLabel(
                timer.isActive
                    ? (timer.isPaused ? String(localized: "Timer paused") : String(localized: "Timer running"))
                    : String(localized: "TaskTracker")
            )
        }
        .contextMenu {
            Button(String(localized: "Quit TaskTracker")) {
                NSApp.terminate(nil)
            }
        }
    }
}

private enum MenuBarPanelTab: String, CaseIterable, Identifiable {
    case today
    case timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .timer: String(localized: "Timer")
        }
    }
}

private struct MenuBarPanel: View {
    let timer: ActiveTimerController
    let today: TodayController
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: MenuBarPanelTab = .today
    /// One-shot per panel appearance — reset on disappear so a later reopen can prefer Timer when
    /// active, without fighting a manual tab change while the panel stays open.
    @State private var didApplyInitialTab = false

    @State private var editingTaskID: UUID?
    @State private var editTitle = ""
    @State private var editNotes = ""
    @State private var editIsScheduled = true
    @State private var editScheduledDate = Date()
    @State private var editPriority: TaskPriority = .none
    @State private var editTimerMinutes = 25

    private static let timerPresets = [15, 25, 30, 45, 60]

    var body: some View {
        Group {
            if let editingID = editingTaskID,
               let editingTask = today.tasks.first(where: { $0.id == editingID }) {
                // Full-panel cover: tabs / list / Open Tasks are replaced by the editor.
                MenuBarTaskEditForm(
                    title: $editTitle,
                    notes: $editNotes,
                    isScheduled: $editIsScheduled,
                    scheduledDate: $editScheduledDate,
                    priority: $editPriority,
                    timerPresetMinutes: $editTimerMinutes,
                    timerPresets: Self.timerPresets,
                    isTimerActive: timer.isActive,
                    isTimerPaused: timer.isPaused,
                    onCancel: { clearEdit() },
                    onSave: {
                        let trimmedTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let day: DayKey? = editIsScheduled
                            ? DayKey.from(date: editScheduledDate)
                            : nil
                        Swift.Task {
                            await today.edit(
                                editingTask,
                                title: trimmedTitle,
                                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                                scheduledDay: day,
                                priority: editPriority,
                                applyScheduleAndPriority: true
                            )
                        }
                        clearEdit()
                    },
                    onStartTimer: {
                        Swift.Task {
                            await timer.start(
                                duration: TimeInterval(editTimerMinutes * 60),
                                relatedTaskID: editingTask.id
                            )
                        }
                        clearEdit()
                    },
                    onDelete: {
                        Swift.Task {
                            await today.delete(editingTask)
                        }
                        clearEdit()
                    }
                )
                .padding(AppSpacing.m)
                .frame(minWidth: 330, minHeight: 360)
                // Keep children queryable — a bare identifier on this wrapper absorbs TextField IDs
                // into `menubar.today.editCover` on macOS MenuBarExtra.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("menubar.today.editCover")
            } else {
                browseContent
            }
        }
        .panelChromeSurface()
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            didApplyInitialTab = false
            clearEdit()
        }
        .task {
            await today.reload()
            await timer.reload()
            guard !didApplyInitialTab else { return }
            didApplyInitialTab = true
            if timer.isActive {
                selectedTab = .timer
            }
        }
    }

    private var browseContent: some View {
        VStack(spacing: AppSpacing.m) {
            Picker("Panel tab", selection: $selectedTab) {
                ForEach(MenuBarPanelTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("menubar.panel.tabPicker")

            Group {
                switch selectedTab {
                case .today:
                    MenuBarTodaySection(
                        today: today,
                        onOpenDetails: beginEdit,
                        onRun: { task in
                            Swift.Task {
                                await timer.start(relatedTaskID: task.id)
                            }
                            selectedTab = .timer
                        }
                    )
                case .timer:
                    TimerSectionView(
                        timer: timer,
                        controlDiameter: 56,
                        displayFontSize: 36,
                        useKeyboardShortcuts: true,
                        showsStopwatch: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            Button {
                // LSUIElement accessory apps don't reliably bring a newly-opened Window to the
                // front on their own — without this, `openWindow` can succeed while the window
                // stays behind other apps or never becomes key, which reads as "nothing happens".
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: TaskTrackerMacApp.taskHubWindowID)
            } label: {
                Text("Open Tasks")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.m)
                    .padding(.vertical, AppSpacing.s)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: [.command])
            .floatingControlSurface()
            .accessibilityLabel(String(localized: "Open task hub"))
            .accessibilityIdentifier("menubar.openTasksButton")
        }
        .padding(AppSpacing.m)
        .frame(minWidth: 330)
    }

    private func beginEdit(_ task: Task) {
        editTitle = task.title
        editNotes = task.notes ?? ""
        editIsScheduled = task.scheduledDay != nil
        editScheduledDate = task.scheduledDay?.date() ?? Date()
        editPriority = task.priority
        editTimerMinutes = 25
        editingTaskID = task.id
    }

    private func clearEdit() {
        editingTaskID = nil
    }
}

private struct MenuBarTodaySection: View {
    @Bindable var today: TodayController
    let onOpenDetails: (Task) -> Void
    let onRun: (Task) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("Today")
                .font(.headline)

            HStack(spacing: AppSpacing.s) {
                Image(systemName: AppSymbols.Tasks.add)
                    .foregroundStyle(Color.accentColor)
                TextField("New reminder", text: $draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, AppSpacing.xs)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                    .accessibilityIdentifier("menubar.today.newTaskField")
                    .onSubmit {
                        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        draft = ""
                        Swift.Task { await today.quickAdd(title: title) }
                    }
            }

            if today.tasks.isEmpty {
                Text(String(localized: "No tasks for today."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.s) {
                        ForEach(today.tasks) { task in
                            HStack(spacing: AppSpacing.s) {
                                // Completion is circle-only — title opens details instead.
                                Button {
                                    Swift.Task {
                                        if task.isCompleted {
                                            await today.uncomplete(task)
                                        } else {
                                            await today.complete(task)
                                        }
                                    }
                                } label: {
                                    TaskCompletionMark(isCompleted: task.isCompleted, tint: .accentColor)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(task.isCompleted ? String(localized: "Mark incomplete") : String(localized: "Mark complete"))
                                .accessibilityLabel(
                                    String(localized: "\(task.title), \(task.isCompleted ? String(localized: "Mark incomplete") : String(localized: "Mark complete"))")
                                )
                                .accessibilityIdentifier("menubar.today.completeButton")

                                Button {
                                    onOpenDetails(task)
                                } label: {
                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        Text(task.title)
                                            .strikethrough(task.isCompleted)
                                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                            .multilineTextAlignment(.leading)
                                        if let notes = task.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Open details"))
                                .accessibilityLabel(String(localized: "Open details for \(task.title)"))
                                .accessibilityIdentifier("menubar.today.taskDetailsButton")

                                // Always enabled: starting while another session is active supersedes it
                                // (docs/TIMER_ARCHITECTURE.md). Pause/Resume continues the same session.
                                Button {
                                    onRun(task)
                                } label: {
                                    Image(systemName: AppSymbols.Timer.resume)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help(String(localized: "Run (replaces any current focus session)"))
                                .accessibilityLabel(String(localized: "Run \(task.title)"))
                                .accessibilityIdentifier("menubar.today.runButton")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44, maxHeight: 220)
            }
        }
    }
}

private struct MenuBarTaskEditForm: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var isScheduled: Bool
    @Binding var scheduledDate: Date
    @Binding var priority: TaskPriority
    @Binding var timerPresetMinutes: Int
    let timerPresets: [Int]
    let isTimerActive: Bool
    let isTimerPaused: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    let onStartTimer: () -> Void
    var onDelete: (() -> Void)? = nil
    @FocusState private var titleFocused: Bool
    @State private var isConfirmingDelete = false

    var body: some View {
        // Full-panel edit cover. Scroll the fields; keep Cancel/Save pinned so a tall form
        // (timer hint, date picker, notes) never traps actions below the MenuBarExtra clip.
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Edit Task")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        .focused($titleFocused)
                        .accessibilityLabel("Title")
                        .accessibilityIdentifier("menubar.today.editForm.titleField")
                        .accessibilityValue(title)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        .accessibilityIdentifier("menubar.today.editForm.notesField")

                    Toggle("Scheduled", isOn: $isScheduled)
                        .accessibilityIdentifier("menubar.today.editForm.scheduledToggle")
                    if isScheduled {
                        DatePicker(
                            "Day",
                            selection: $scheduledDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("menubar.today.editForm.datePicker")
                    } else {
                        Text(String(localized: "Unscheduled tasks move to the Pool."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .accessibilityIdentifier("menubar.today.editForm.priorityPicker")

                    HStack(spacing: AppSpacing.s) {
                        Picker("Timer", selection: $timerPresetMinutes) {
                            ForEach(timerPresets, id: \.self) { minutes in
                                Text("\(minutes)m").tag(minutes)
                            }
                        }
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("menubar.today.editForm.timerPresetPicker")

                        // Start is always available: an active/paused session is superseded (not blocked).
                        // Pause + Resume on the Timer tab continues the same session; Stop ends it for good.
                        Button(isTimerActive ? String(localized: "Replace Timer") : String(localized: "Start Timer"), action: onStartTimer)
                            .padding(.horizontal, AppSpacing.m)
                            .padding(.vertical, AppSpacing.s)
                            .floatingControlSurface()
                            .accessibilityIdentifier("menubar.today.editForm.startTimerButton")
                    }

                    if isTimerActive {
                        Text(
                            isTimerPaused
                                ? String(localized: "A focus session is paused. Resume it from the Timer tab to continue, or replace it here. Stop ends it permanently.")
                                : String(localized: "A focus session is running. Use Pause/Resume on the Timer tab to continue later. Starting here replaces it.")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("menubar.today.editForm.timerHint")
                    }

                    if onDelete != nil {
                        Divider()

                        Button(String(localized: "Delete Task"), role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("menubar.today.editForm.deleteButton")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, AppSpacing.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("menubar.today.editForm.scroll")

            SurfaceGroup {
                HStack(spacing: AppSpacing.s) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("menubar.today.editForm.cancelButton")
                    Button("Save", action: onSave)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.vertical, AppSpacing.s)
                        .floatingControlSurface()
                        .tint(.accentColor)
                        .accessibilityIdentifier("menubar.today.editForm.saveButton")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            String(localized: "Delete this task?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Task"), role: .destructive) { onDelete?() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .task { titleFocused = true }
    }
}
