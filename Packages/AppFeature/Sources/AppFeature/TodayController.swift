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
            if let existing = try await existingActiveTask(titled: title) {
                let scheduled = TaskService.scheduleForToday(existing, now: timeSource.now, calendar: calendar)
                try await repository.upsert(scheduled)
                await reload()
                return
            }

            let created = try TaskService.create(title: title, now: timeSource.now)
            let scheduled = TaskService.scheduleForToday(created, now: timeSource.now, calendar: calendar)
            try await repository.upsert(scheduled)
            await reload()
        } catch { return }
    }

    public func scheduleForToday(_ task: Task) async {
        do {
            let scheduled = TaskService.scheduleForToday(task, now: timeSource.now, calendar: calendar)
            try await repository.upsert(scheduled)
            await reload()
        } catch { return }
    }

    public func removeFromToday(_ task: Task) async {
        do {
            let unscheduled = TaskService.unschedule(task, now: timeSource.now)
            try await repository.upsert(unscheduled)
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

    private func existingActiveTask(titled title: String) async throws -> Task? {
        let target = Self.normalizedTitle(title)
        guard !target.isEmpty else { return nil }
        return try await repository.allTasks().first {
            $0.completedAt == nil && Self.normalizedTitle($0.title) == target
        }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
