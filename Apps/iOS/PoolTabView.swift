import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

struct PoolTabView: View {
    @Bindable var pool: PoolController
    let today: TodayController
    let timer: ActiveTimerController
    @Binding var taskIDToPresent: UUID?
    @Binding var presentedTaskID: UUID?
    var makeTimeLog: ((UUID) -> TaskTimeLogController)?
    var onStartedTimer: (() -> Void)? = nil
    var onOpenTimerTab: (() -> Void)? = nil
    @State private var editingTask: Task?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PoolControlPanel(
                    showMode: $pool.showMode,
                    sortOrder: $pool.sortOrder,
                    count: { pool.count(for: $0) },
                    onShowModeChanged: {
                        Swift.Task { await pool.reload() }
                    }
                )
                .padding(.horizontal, AppSpacing.m)
                .padding(.top, AppSpacing.s)

                ZStack {
                    List {
                        Section {
                            ForEach(pool.visibleTasks) { task in
                                poolRow(task)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)

                    if pool.visibleTasks.isEmpty {
                        PoolEmptyState(showMode: pool.showMode)
                    }
                }
            }
            .navigationTitle("Pool")
            .sheet(item: $editingTask, onDismiss: { presentedTaskID = nil }) { task in
                TaskEditSheet(
                    task: task,
                    timer: timer,
                    makeTimeLog: makeTimeLog,
                    onSave: { values in
                        let notes = values.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        await pool.edit(
                            task,
                            title: values.title,
                            notes: notes.isEmpty ? nil : notes,
                            scheduledDay: values.scheduledDay,
                            priority: values.priority,
                            applyScheduleAndPriority: true
                        )
                        await today.reload()
                    },
                    onDelete: {
                        await pool.delete(task)
                        await today.reload()
                    },
                    onStartedTimer: onStartedTimer,
                    onOpenTimerTab: onOpenTimerTab
                )
            }
            .task { await pool.reload() }
            .onChange(of: editingTask) { _, task in
                presentedTaskID = task?.id
            }
            .onChange(of: taskIDToPresent) { _, id in
                presentTaskIfNeeded(id)
            }
            .onChange(of: pool.tasks) { _, _ in
                presentTaskIfNeeded(taskIDToPresent)
            }
        }
    }

    @ViewBuilder
    private func poolRow(_ task: Task) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            Button {
                Swift.Task {
                    if task.isCompleted {
                        await pool.uncomplete(task)
                        await today.reload()
                    } else {
                        await pool.archive(task)
                        await today.reload()
                    }
                }
            } label: {
                TaskCompletionMark(isCompleted: task.isCompleted, tint: .accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark done")

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    if task.priority != .none {
                        Text(task.priority.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editingTask = task }
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture { editingTask = task }
                }
            }
            Spacer()
            if pool.needsTodayAction(for: task) {
                Button {
                    Swift.Task {
                        await pool.scheduleForToday(task)
                        await today.reload()
                    }
                } label: {
                    Image(systemName: AppSymbols.Navigation.today)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add to Today")
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { editingTask = task }
        .swipeActions(edge: .leading, allowsFullSwipe: !task.isCompleted) {
            if !task.isCompleted {
                Button {
                    Swift.Task {
                        await pool.archive(task)
                        await today.reload()
                    }
                } label: {
                    Image(systemName: AppSymbols.Tasks.complete)
                }
                .accessibilityLabel("Done")
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: !task.isCompleted) {
            if !task.isCompleted {
                Button {
                    Swift.Task {
                        await pool.archive(task)
                        await today.reload()
                    }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.orange)
            } else {
                Button {
                    Swift.Task {
                        await pool.uncomplete(task)
                        await today.reload()
                    }
                } label: {
                    Label("Reopen", systemImage: AppSymbols.Tasks.incomplete)
                        .labelStyle(.titleAndIcon)
                }
                .tint(.accentColor)
            }

            Button(role: .destructive) {
                Swift.Task { await pool.delete(task) }
            } label: {
                Label("Delete", systemImage: AppSymbols.Tasks.delete)
                    .labelStyle(.titleAndIcon)
            }
        }
        .contextMenu {
            if !task.isCompleted {
                Button {
                    Swift.Task {
                        await pool.scheduleForToday(task)
                        await today.reload()
                    }
                } label: {
                    Label("Schedule for Today", systemImage: AppSymbols.Navigation.today)
                }

                Button {
                    Swift.Task { @MainActor in
                        await timer.start(relatedTaskID: task.id)
                        onStartedTimer?()
                    }
                } label: {
                    Label("Start Timer", systemImage: AppSymbols.Timer.resume)
                }
            } else {
                Button {
                    Swift.Task {
                        await pool.uncomplete(task)
                        await today.reload()
                    }
                } label: {
                    Label("Mark Incomplete", systemImage: AppSymbols.Tasks.incomplete)
                }
            }

            Button(role: .destructive) {
                Swift.Task { await pool.delete(task) }
            } label: {
                Label("Delete", systemImage: AppSymbols.Tasks.delete)
            }
        }
    }

    private func presentTaskIfNeeded(_ id: UUID?) {
        guard let id else { return }
        guard let task = pool.tasks.first(where: { $0.id == id })
            ?? pool.visibleTasks.first(where: { $0.id == id }) else { return }
        editingTask = task
        presentedTaskID = id
        taskIDToPresent = nil
    }
}

private struct PoolControlPanel: View {
    @Binding var showMode: PoolShowMode
    @Binding var sortOrder: PoolSortOrder
    let count: (PoolShowMode) -> Int
    let onShowModeChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.s) {
                ForEach(PoolShowMode.allCases) { mode in
                    PoolCategoryCard(
                        mode: mode,
                        count: count(mode),
                        isSelected: showMode == mode
                    ) {
                        showMode = mode
                        onShowModeChanged()
                    }
                }
            }
            .accessibilityIdentifier("pool.showMode")

            Menu {
                ForEach(PoolSortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(
                            order.displayName,
                            systemImage: sortOrder == order ? "checkmark" : "circle"
                        )
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.s) {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(sortOrder.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.16), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pool.sortMenu")
        }
        .padding(AppSpacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PoolCategoryCard: View {
    let mode: PoolShowMode
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    private var symbolName: String {
        switch mode {
        case .today: return AppSymbols.Navigation.today
        case .allTasks: return AppSymbols.Navigation.pool
        case .scheduled: return "calendar"
        case .archived: return "archivebox"
        case .completed: return AppSymbols.Tasks.complete
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                HStack {
                    Image(systemName: symbolName)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    Text("\(count)")
                        .font(.headline.monospacedDigit())
                }

                Text(mode.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(mode.displayName)")
        .accessibilityValue("\(count) tasks")
    }
}

private struct PoolEmptyState: View {
    let showMode: PoolShowMode

    private var title: String {
        switch showMode {
        case .today: return "Nothing in Today"
        case .allTasks: return "Pool is empty"
        case .scheduled: return "No scheduled tasks"
        case .archived: return "No archived tasks"
        case .completed: return "No completed tasks"
        }
    }

    private var message: String {
        switch showMode {
        case .today:
            return "Tasks scheduled for today will appear here."
        case .allTasks:
            return "Add a task when something comes to mind. Active tasks, including Today tasks, will live here."
        case .scheduled:
            return "Tasks with a scheduled day will appear here."
        case .archived:
            return "Archived tasks will appear here. In this version, archive uses the completed task state."
        case .completed:
            return "Tasks you finish will appear here."
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: AppSymbols.Navigation.pool)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Pool — All Tasks") {
    let pool = PreviewMocks.pool()
    PoolTabView(
        pool: pool,
        today: PreviewMocks.today(),
        timer: PreviewMocks.idleTimer(),
        taskIDToPresent: .constant(nil),
        presentedTaskID: .constant(nil)
    )
    .task { await pool.reload() }
}

#Preview("Pool — Completed") {
    let pool = PreviewMocks.pool(showMode: .completed)
    PoolTabView(
        pool: pool,
        today: PreviewMocks.today(),
        timer: PreviewMocks.idleTimer(),
        taskIDToPresent: .constant(nil),
        presentedTaskID: .constant(nil)
    )
    .task { await pool.reload() }
}

#Preview("Pool — Search Filter") {
    let pool = PreviewMocks.pool(searchText: "renew")
    PoolTabView(
        pool: pool,
        today: PreviewMocks.today(),
        timer: PreviewMocks.idleTimer(),
        taskIDToPresent: .constant(nil),
        presentedTaskID: .constant(nil)
    )
    .task { await pool.reload() }
}
#endif
