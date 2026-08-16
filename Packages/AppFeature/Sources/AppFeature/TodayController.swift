import Foundation
import TaskDomain

@Observable
@MainActor
public final class TodayController {
    public private(set) var tasks: [Task] = []

    private let repository: any TaskRepository
    private let timeSource: any TimeSource
    private let calendar: Calendar

    public init(
        repository: any TaskRepository,
        timeSource: any TimeSource = SystemTimeSource(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.timeSource = timeSource
        self.calendar = calendar
    }

    public func reload() async {
        do {
            let today = DayKey.from(date: timeSource.now, calendar: calendar)
            tasks = try await repository.tasks(scheduledFor: today).sorted { $0.createdAt < $1.createdAt }
        } catch {
            tasks = []
        }
    }

    public func quickAdd(title: String) async {
        do {
            let created = try TaskService.create(title: title, now: timeSource.now)
            let scheduled = TaskService.scheduleForToday(created, now: timeSource.now, calendar: calendar)
            try await repository.upsert(scheduled)
            await reload()
        } catch { return }
    }

    public func complete(_ task: Task) async {
        do {
            let updated = try TaskService.complete(task, now: timeSource.now)
            try await repository.upsert(updated)
            await reload()
        } catch { return }
    }

    public func uncomplete(_ task: Task) async {
        do {
            let updated = TaskService.uncomplete(task, now: timeSource.now)
            try await repository.upsert(updated)
            await reload()
        } catch { return }
    }

    public func delete(_ task: Task) async {
        do {
            try await repository.deleteTask(id: task.id)
            await reload()
        } catch { return }
    }

    public func edit(
        _ task: Task,
        title: String,
        notes: String?,
        scheduledDay: DayKey? = nil,
        priority: TaskPriority = .none,
        applyScheduleAndPriority: Bool = false
    ) async {
        do {
            let updated = try TaskService.edit(
                task,
                title: title,
                notes: notes,
                now: timeSource.now,
                scheduledDay: scheduledDay,
                priority: priority,
                applyScheduleAndPriority: applyScheduleAndPriority
            )
            try await repository.upsert(updated)
            await reload()
        } catch { return }
    }
}
