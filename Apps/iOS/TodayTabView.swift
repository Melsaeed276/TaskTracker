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
    @State private var editingTask: Task?
    @State private var completingTaskIDs = Set<UUID>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(today.tasks) { task in
                        let isShowingCompleted = task.isCompleted || completingTaskIDs.contains(task.id)
                        TaskRow(
                            title: task.title,
                            notes: task.notes,
                            isCompleted: isShowingCompleted,
                            leading: TaskRow.LeadingAction(
                                isOn: isShowingCompleted,
                                tint: .accentColor
                            ) {
                                Swift.Task {
                                    if task.isCompleted {
                                        await today.uncomplete(task)
                                    } else {
                                        await completeWithRowAnimation(task)
                                    }
                                }
                            },
                            onPress: { editingTask = task },
                            completionAnimationPhaseDurationNanoseconds: completionAnimationDurationNanoseconds
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            swipeButton(completionSwipeAction(for: task, isShowingCompleted: isShowingCompleted))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            swipeButton(.standardRemoveFromToday(task: task, today: today))
                        }
                    }
                }
            }
            .overlay {
                if today.tasks.isEmpty {
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

    @MainActor
    private func completeWithRowAnimation(_ task: Task) async {
        guard !completingTaskIDs.contains(task.id) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            _ = completingTaskIDs.insert(task.id)
        }

        // Let TaskRow's checkmark/burst animation play before the Today query removes
        // the completed task from this filtered list.
        try? await Swift.Task.sleep(nanoseconds: completionAnimationDurationNanoseconds)

        await today.complete(task)
        await pool.reload()
        completingTaskIDs.remove(task.id)
    }

    private func completionSwipeAction(for task: Task, isShowingCompleted: Bool) -> TodayRowSwipeAction {
        TodayRowSwipeAction(
            systemImage: isShowingCompleted ? AppSymbols.Tasks.incomplete : AppSymbols.Tasks.complete,
            accessibilityLabel: isShowingCompleted ? String(localized: "Mark not done") : String(localized: "Done"),
            tint: .green
        ) {
            if task.isCompleted {
                await today.uncomplete(task)
            } else {
                await completeWithRowAnimation(task)
            }
        }
    }

    private var completionAnimationDurationNanoseconds: UInt64 {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ? 1_600_000_000 : 700_000_000
    }

    private func swipeButton(_ action: TodayRowSwipeAction) -> some View {
        Button {
            Swift.Task { await action.perform() }
        } label: {
            Image(systemName: action.systemImage)
        }
        .accessibilityLabel(action.accessibilityLabel)
        .tint(action.tint)
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

/// One revealed swipe action on a Today row, described as plain values so the row
/// controls styling, tint, and accessibility.
private struct TodayRowSwipeAction {
    let systemImage: String
    let accessibilityLabel: String
    /// Nil inherits the accent color.
    let tint: Color?
    let perform: () async -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        tint: Color? = nil,
        perform: @escaping () async -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.perform = perform
    }

    /// Default leading (left-to-right swipe) action: toggle completion.
    static func standardCompletion(
        task: Task,
        today: TodayController,
        onFinish: @escaping () async -> Void
    ) -> TodayRowSwipeAction {
        TodayRowSwipeAction(
            systemImage: task.isCompleted ? AppSymbols.Tasks.incomplete : AppSymbols.Tasks.complete,
            accessibilityLabel: task.isCompleted ? String(localized: "Mark not done") : String(localized: "Done"),
            tint: .green
        ) {
            if task.isCompleted {
                await today.uncomplete(task)
            } else {
                await today.complete(task)
                await onFinish()
            }
        }
    }

    /// Default trailing (right-to-left swipe) action: remove the task from Today.
    static func standardRemoveFromToday(task: Task, today: TodayController) -> TodayRowSwipeAction {
        TodayRowSwipeAction(
            systemImage: AppSymbols.Tasks.removeFromToday,
            accessibilityLabel: String(localized: "Remove from Today"),
            tint: .orange
        ) {
            await today.removeFromToday(task)
        }
    }
}

#if DEBUG
// MARK: - TodayTabView previews

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
