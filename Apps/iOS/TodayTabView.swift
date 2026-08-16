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
    @State private var draft = ""
    @State private var editingTask: Task?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: AppSymbols.Tasks.add)
                            .foregroundStyle(Color.accentColor)
                            .font(.headline)
                        TextField("New task", text: $draft)
                            .submitLabel(.done)
                            .accessibilityIdentifier("today.newTaskField")
                            .onSubmit {
                                let title = draft
                                draft = ""
                                Swift.Task { await today.quickAdd(title: title) }
                            }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

                Section {
                    ForEach(today.tasks) { task in
                        TodayTaskRow(task: task, today: today, onEdit: { editingTask = task })
                    }
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
}

private struct TodayTaskRow: View {
    let task: Task
    let today: TodayController
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            // A `Button` sharing a row with an outer `.onTapGesture` is a well-known SwiftUI
            // conflict — hit-testing between the two becomes unreliable, so the edit gesture is
            // scoped to the title text only, leaving the completion button's tap area untouched.
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
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEdit)

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onEdit)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
