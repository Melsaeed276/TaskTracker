import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

struct TodayTabView: View {
    @Bindable var today: TodayController
    let pool: PoolController
    let timer: ActiveTimerController
    @Binding var taskIDToPresent: UUID?
    /// Currently open edit sheet task, if any (for hiding the app-wide timer bar).
    @Binding var presentedTaskID: UUID?
    var makeTimeLog: ((UUID) -> TaskTimeLogController)?
    var onStartedTimer: (() -> Void)? = nil
    var onOpenTimerTab: (() -> Void)? = nil
    var onOpenPoolTab: (() -> Void)? = nil
    @State private var draft = ""
    @State private var editingTask: Task?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(today.tasks) { task in
                        TodayTaskRow(
                            task: task,
                            today: today,
                            onComplete: { await pool.reload() },
                            onEdit: { editingTask = task }
                        )
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TaskQuickEntryView(
                    placeholder: "Add or search task",
                    draft: $draft,
                    suggestions: matchingActiveTasks,
                    onSubmit: { title in
                        Swift.Task {
                            await today.quickAdd(title: title)
                            await pool.reload()
                        }
                    },
                    onSelectSuggestion: { task in
                        draft = ""
                        Swift.Task {
                            await today.scheduleForToday(task)
                            await pool.reload()
                        }
                    }
                )
                .accessibilityIdentifier("today.newTaskField")
            }
            .overlay {
                if today.tasks.isEmpty && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    TodayEmptyState(onOpenPoolTab: onOpenPoolTab)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .sheet(item: $editingTask, onDismiss: { presentedTaskID = nil }) { task in
                TaskEditSheet(
                    task: task,
                    timer: timer,
                    makeTimeLog: makeTimeLog,
                    onSave: { values in
                        let notes = values.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        await today.edit(
                            task,
                            title: values.title,
                            notes: notes.isEmpty ? nil : notes,
                            scheduledDay: values.scheduledDay,
                            priority: values.priority,
                            applyScheduleAndPriority: true
                        )
                        await pool.reload()
                    },
                    onDelete: {
                        await today.delete(task)
                        await pool.reload()
                    },
                    onStartedTimer: onStartedTimer,
                    onOpenTimerTab: onOpenTimerTab
                )
            }
            .task { await today.reload() }
            .onChange(of: editingTask) { _, task in
                presentedTaskID = task?.id
            }
            .onChange(of: taskIDToPresent) { _, id in
                presentTaskIfNeeded(id)
            }
            .onChange(of: today.tasks) { _, _ in
                presentTaskIfNeeded(taskIDToPresent)
            }
        }
    }

    private func presentTaskIfNeeded(_ id: UUID?) {
        guard let id else { return }
        guard let task = today.tasks.first(where: { $0.id == id }) else { return }
        editingTask = task
        presentedTaskID = id
        taskIDToPresent = nil
    }

    private var matchingActiveTasks: [Task] {
        let query = normalized(draft)
        guard !query.isEmpty else { return [] }
        return pool.tasks.filter {
            !$0.isCompleted && normalized($0.title).contains(query)
        }
    }

    private func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}

private struct TodayEmptyState: View {
    let onOpenPoolTab: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: AppSymbols.Navigation.today)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.xs) {
                Text("Nothing planned today")
                    .font(.title3.weight(.semibold))

                Text("Pick tasks from the Pool when you are ready to plan your day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                onOpenPoolTab?()
            } label: {
                Label("Open Pool", systemImage: AppSymbols.Navigation.pool)
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("today.empty.openPool")
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TodayTaskRow: View {
    let task: Task
    let today: TodayController
    let onComplete: () async -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            Button {
                Swift.Task {
                    await today.complete(task)
                    await onComplete()
                }
            } label: {
                TaskCompletionMark(isCompleted: task.isCompleted, tint: .accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.isCompleted ? "Completed" : "Mark done")

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Swift.Task {
                    await today.complete(task)
                    await onComplete()
                }
            } label: {
                Image(systemName: AppSymbols.Tasks.complete)
            }
            .accessibilityLabel("Done")
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Swift.Task { await today.removeFromToday(task) }
            } label: {
                Label("Remove Today", systemImage: "calendar.badge.minus")
                    .labelStyle(.titleAndIcon)
            }
            .tint(.orange)
        }
    }
}

#if DEBUG
#Preview("Today — Populated") {
    let today = PreviewMocks.today()
    TodayTabView(
        today: today,
        pool: PreviewMocks.pool(),
        timer: PreviewMocks.idleTimer(),
        taskIDToPresent: .constant(nil),
        presentedTaskID: .constant(nil)
    )
    .task { await today.reload() }
}

#Preview("Today — Empty") {
    let today = PreviewMocks.today([])
    TodayTabView(
        today: today,
        pool: PreviewMocks.pool(),
        timer: PreviewMocks.idleTimer(),
        taskIDToPresent: .constant(nil),
        presentedTaskID: .constant(nil)
    )
    .task { await today.reload() }
}
#endif
