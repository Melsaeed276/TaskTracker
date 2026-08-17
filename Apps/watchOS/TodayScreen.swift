import SwiftUI
import AppDesign
import AppFeature
import TaskDomain

struct TodayScreen: View {
    let today: TodayController
    let timer: ActiveTimerController

    var body: some View {
        List {
            if today.tasks.isEmpty {
                Text("No tasks today")
                    .foregroundStyle(.secondary)
            }

            ForEach(today.tasks) { task in
                TodayRow(
                    task: task,
                    onTap: { toggle(task) },
                    onLongPress: { startTimer(for: task) }
                )
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .listStyle(.carousel)
        .task { await today.reload() }
    }

    private func toggle(_ task: Task) {
        Swift.Task {
            if task.isCompleted {
                await today.uncomplete(task)
            } else {
                await today.complete(task)
            }
            await today.reload()
        }
    }

    private func startTimer(for task: Task) {
        // Start while another session is active supersedes it (docs/TIMER_ARCHITECTURE.md).
        Swift.Task {
            await timer.start(relatedTaskID: task.id)
            await timer.reload()
        }
    }
}
private struct TodayRow: View {
    let task: Task
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            TaskCompletionMark(isCompleted: task.isCompleted, tint: .green)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in onLongPress() }
        )
        .accessibilityLabel(task.title)
        .accessibilityHint("Tap to complete, long press to start timer")
    }
}

#if DEBUG
#Preview("Today — Populated") {
    let today = PreviewMocks.today()
    TodayScreen(today: today, timer: PreviewMocks.idleTimer())
        .task { await today.reload() }
}

#Preview("Today — Empty") {
    let today = PreviewMocks.today([])
    TodayScreen(today: today, timer: PreviewMocks.idleTimer())
        .task { await today.reload() }
}
#endif
