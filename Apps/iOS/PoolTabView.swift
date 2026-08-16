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
    @State private var draft = ""
    @State private var editingTask: Task?

    var body: some View {
        NavigationStack {
            List {
                if pool.showMode == .active {
                    Section {
                        HStack(spacing: AppSpacing.s) {
                            Image(systemName: AppSymbols.Tasks.add)
                                .foregroundStyle(Color.accentColor)
                                .font(.headline)
                            TextField("New reminder", text: $draft)
                                .submitLabel(.done)
                                .accessibilityIdentifier("pool.newTaskField")
                                .onSubmit {
                                    let title = draft
                                    draft = ""
                                    Swift.Task { await pool.quickAdd(title: title) }
                                }
                        }
                        .padding(.vertical, AppSpacing.xs)
                        Text("Unscheduled reminders live here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(pool.visibleTasks) { task in
                        poolRow(task)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pool")
            .searchable(text: $pool.searchText, prompt: "Search Pool")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Show", selection: $pool.showMode) {
                        ForEach(PoolShowMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("pool.showMode")
                    .onChange(of: pool.showMode) { _, _ in
                        Swift.Task { await pool.reload() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(PoolSortOrder.allCases) { order in
                            Button {
                                pool.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.displayName)
                                    if pool.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("pool.sortMenu")
                }
            }
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
                    }
                }
            } label: {
                TaskCompletionMark(isCompleted: task.isCompleted, tint: .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(!task.isCompleted)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Incomplete")

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
            if pool.showMode == .active {
                Image(systemName: AppSymbols.Tasks.scheduleToday)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { editingTask = task }
        .swipeActions(edge: .trailing, allowsFullSwipe: pool.showMode == .active) {
            if pool.showMode == .active {
                Button {
                    Swift.Task {
                        await pool.scheduleForToday(task)
                        await today.reload()
                    }
                } label: {
                    Label("Today", systemImage: AppSymbols.Tasks.scheduleToday)
                }
                .tint(.accentColor)
            } else {
                Button {
                    Swift.Task {
                        await pool.uncomplete(task)
                        await today.reload()
                    }
                } label: {
                    Label("Reopen", systemImage: AppSymbols.Tasks.incomplete)
                }
                .tint(.accentColor)
            }

            Button(role: .destructive) {
                Swift.Task { await pool.delete(task) }
            } label: {
                Label("Delete", systemImage: AppSymbols.Tasks.delete)
            }
        }
        .contextMenu {
            if pool.showMode == .active {
                Button {
                    Swift.Task {
                        await pool.scheduleForToday(task)
                        await today.reload()
                    }
                } label: {
                    Label("Schedule for Today", systemImage: AppSymbols.Tasks.scheduleToday)
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
