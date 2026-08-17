import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

struct TaskHubView: View {
    let today: TodayController
    let pool: PoolController
    let timer: ActiveTimerController
    @State private var selection: TaskHubSection? = .today

    private enum TaskHubSection: String, CaseIterable, Identifiable {
        case today
        case pool
        case timer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .pool: return "Pool"
            case .timer: return "Timer"
            }
        }

        var symbol: String {
            switch self {
            case .today: return AppSymbols.Navigation.today
            case .pool: return AppSymbols.Navigation.pool
            case .timer: return AppSymbols.Navigation.timer
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(TaskHubSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("Task Tracker")
            .frame(minWidth: 190)
        } detail: {
            Group {
                switch selection ?? .today {
                case .today:
                    TodayPane(today: today, pool: pool, timer: timer)
                case .pool:
                    PoolPane(pool: pool, today: today, timer: timer)
                case .timer:
                    TimerPane(timer: timer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        // Settings lives in the app now, not the menu-bar panel — this toolbar entry is the
        // explicit, discoverable path; the standard "TaskTracker" app-menu Settings… item (⌘,)
        // that SwiftUI's `Settings { }` scene already contributes automatically once this window
        // has focus is the other, already-working path — nothing extra needed for that one.
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: AppSymbols.Navigation.settings)
                }
                .help("Preferences")
                .accessibilityLabel("Preferences")
                .accessibilityIdentifier("taskHub.settingsButton")
            }
        }
        .task {
            await today.reload()
            await pool.reload()
            await timer.reload()
        }
    }
}
private struct TodayPane: View {
    @Bindable var today: TodayController
    let pool: PoolController
    let timer: ActiveTimerController
    @State private var draft = ""
    @State private var selection: Task.ID?
    @State private var editTitle = ""
    @State private var editNotes = ""
    @State private var editIsScheduled = true
    @State private var editScheduledDate = Date()
    @State private var editPriority: TaskPriority = .none
    @State private var editTimerMinutes = 25
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case draft
        case editTitle
        case editNotes
    }

    private static let timerPresets = [15, 25, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Today")
                .font(.title3.weight(.semibold))

            HStack(spacing: AppSpacing.s) {
                Image(systemName: AppSymbols.Tasks.add)
                    .foregroundStyle(Color.accentColor)
                TextField("New reminder", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .draft)
                    .onSubmit {
                        let title = draft
                        draft = ""
                        Swift.Task { await today.quickAdd(title: title) }
                    }
            }

            List(today.tasks, selection: $selection) { task in
                TodayRow(task: task, today: today)
                    .tag(task.id)
                    .padding(.vertical, AppSpacing.xs)
            }
            .listStyle(.inset)
            .frame(maxHeight: .infinity)

            if let selected = selectedTask {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text("Edit Selected")
                        .font(.headline)
                    TextField("Title", text: $editTitle)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        .focused($focusedField, equals: .editTitle)
                        .onSubmit { focusedField = .editNotes }
                    TextField("Notes", text: $editNotes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        .focused($focusedField, equals: .editNotes)

                    Toggle("Scheduled", isOn: $editIsScheduled)
                    if editIsScheduled {
                        DatePicker(
                            "Day",
                            selection: $editScheduledDate,
                            displayedComponents: .date
                        )
                    }

                    Picker("Priority", selection: $editPriority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }

                    HStack(spacing: AppSpacing.s) {
                        Picker("Timer", selection: $editTimerMinutes) {
                            ForEach(Self.timerPresets, id: \.self) { minutes in
                                Text("\(minutes)m").tag(minutes)
                            }
                        }
                        .frame(maxWidth: 120)
                        Button("Start Timer") {
                            Swift.Task {
                                await timer.start(
                                    duration: TimeInterval(editTimerMinutes * 60),
                                    relatedTaskID: selected.id
                                )
                            }
                        }
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.vertical, AppSpacing.s)
                        .floatingControlSurface()
                        .help(
                            timer.isActive
                                ? "Replaces the current focus session. Use Pause/Resume on Timer to continue later."
                                : "Start a focus timer for this task"
                        )
                    }

                    SurfaceGroup {
                        HStack(spacing: AppSpacing.s) {
                            Button("Cancel") {
                                selection = nil
                                editTitle = ""
                                editNotes = ""
                                focusedField = .draft
                            }
                            Button("Save") {
                                let trimmedTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                                let day: DayKey? = editIsScheduled
                                    ? DayKey.from(date: editScheduledDate)
                                    : nil
                                Swift.Task {
                                    await today.edit(
                                        selected,
                                        title: trimmedTitle,
                                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                                        scheduledDay: day,
                                        priority: editPriority,
                                        applyScheduleAndPriority: true
                                    )
                                    await pool.reload()
                                }
                            }
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .padding(.horizontal, AppSpacing.m)
                            .padding(.vertical, AppSpacing.s)
                            .floatingControlSurface()
                            .tint(.accentColor)
                        }
                    }
                }
                .padding(AppSpacing.m)
                .navigationSurface()
            }
        }
        .padding(AppSpacing.m)
        .onChange(of: selection) { _, newID in
            if let task = today.tasks.first(where: { $0.id == newID }) {
                editTitle = task.title
                editNotes = task.notes ?? ""
                editIsScheduled = task.scheduledDay != nil
                editScheduledDate = task.scheduledDay?.date() ?? Date()
                editPriority = task.priority
                focusedField = .editTitle
            } else {
                focusedField = .draft
            }
        }
        .task { focusedField = .draft }
    }

    private var selectedTask: Task? {
        today.tasks.first(where: { $0.id == selection })
    }
}

private struct TodayRow: View {
    let task: Task
    let today: TodayController

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            // `.borderless` keeps the checkbox tappable inside a selectable `List` row —
            // `.plain` loses the click to row selection on macOS.
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
            }
            .buttonStyle(.borderless)
            .help(task.isCompleted ? "Mark incomplete" : "Mark complete")
            .accessibilityLabel(
                "\(task.title), \(task.isCompleted ? "Mark incomplete" : "Mark complete")"
            )
            .accessibilityIdentifier("taskHub.today.completeButton")

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PoolPane: View {
    @Bindable var pool: PoolController
    let today: TodayController
    let timer: ActiveTimerController
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Pool")
                .font(.title3.weight(.semibold))

            HStack(spacing: AppSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Pool", text: $pool.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: AppSpacing.s) {
                Image(systemName: AppSymbols.Tasks.add)
                    .foregroundStyle(Color.accentColor)
                TextField("New reminder", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let title = draft
                        draft = ""
                        Swift.Task { await pool.quickAdd(title: title) }
                    }
            }

            Text("Unscheduled reminders live here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(pool.unscheduledTasks) { task in
                PoolRow(task: task, pool: pool, today: today, timer: timer)
                    .padding(.vertical, AppSpacing.xs)
            }
            .listStyle(.inset)
        }
        .padding(AppSpacing.m)
    }
}

private struct PoolRow: View {
    let task: Task
    let pool: PoolController
    let today: TodayController
    let timer: ActiveTimerController

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            TaskCompletionMark(isCompleted: false, tint: .accentColor)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(task.title)
                    if task.priority != .none {
                        Text(task.priority.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                Swift.Task {
                    await timer.start(relatedTaskID: task.id)
                }
            } label: {
                Image(systemName: AppSymbols.Timer.resume)
            }
            .buttonStyle(.borderless)
            .help("Start timer for task (replaces any current focus session)")
            .accessibilityLabel("Start timer for task")

            Button {
                Swift.Task {
                    await pool.scheduleForToday(task)
                    await today.reload()
                }
            } label: {
                Image(systemName: AppSymbols.Tasks.scheduleToday)
            }
            .buttonStyle(.borderless)
            .help("Schedule for today")
            .accessibilityLabel("Schedule for today")

            Button(role: .destructive) {
                Swift.Task { await pool.delete(task) }
            } label: {
                Image(systemName: AppSymbols.Tasks.delete)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete task")
        }
    }
}

private struct TimerPane: View {
    let timer: ActiveTimerController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                Text("Timer")
                    .font(.title2.weight(.semibold))

                Text("Use the same timer controls available in the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TimerSectionView(
                    timer: timer,
                    controlDiameter: 72,
                    displayFontSize: 52,
                    dialDiameter: 280
                )
                .padding(AppSpacing.m)
                .navigationSurface()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.l)
        }
    }
}

#if DEBUG
#Preview("Task Hub") {
    TaskHubView(
        today: PreviewMocks.today(),
        pool: PreviewMocks.pool(),
        timer: PreviewMocks.idleTimer()
    )
}
#endif
