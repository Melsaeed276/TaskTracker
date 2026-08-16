import Foundation

public enum TaskService: Sendable {
    public static func create(
        title: String,
        notes: String? = nil,
        now: Date,
        calendar: Calendar = .current
    ) throws -> Task {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskValidationError.emptyTitle }

        let id = UUID()
        return Task(
            id: id,
            title: trimmed,
            notes: notes,
            createdAt: now,
            completedAt: nil,
            scheduledDay: nil,
            priority: .none,
            updatedAt: now
        )
    }

    public static func validate(_ task: Task, now: Date) throws {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskValidationError.emptyTitle }
        if let completedAt = task.completedAt, completedAt > now {
            throw TaskValidationError.completedInFuture
        }
    }

    public static func edit(
        _ task: Task,
        title: String,
        notes: String?,
        now: Date,
        scheduledDay: DayKey? = nil,
        priority: TaskPriority = .none,
        applyScheduleAndPriority: Bool = false
    ) throws -> Task {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskValidationError.emptyTitle }

        var t = task
        t.title = trimmed
        t.notes = notes
        if applyScheduleAndPriority {
            t.scheduledDay = scheduledDay
            t.priority = priority
        }
        t.updatedAt = max(task.updatedAt, now)
        return t
    }

    public static func scheduleForToday(
        _ task: Task,
        now: Date,
        calendar: Calendar = .current
    ) -> Task {
        schedule(task, for: DayKey.from(date: now, calendar: calendar), now: now)
    }

    public static func schedule(
        _ task: Task,
        for day: DayKey,
        now: Date
    ) -> Task {
        var t = task
        t.scheduledDay = day
        t.updatedAt = max(task.updatedAt, now)
        return t
    }

    public static func unschedule(
        _ task: Task,
        now: Date
    ) -> Task {
        var t = task
        t.scheduledDay = nil
        t.updatedAt = max(task.updatedAt, now)
        return t
    }

    public static func complete(
        _ task: Task,
        now: Date
    ) throws -> Task {
        if let completedAt = task.completedAt {
            // Idempotent: already completed.
            var t = task
            t.completedAt = completedAt
            t.updatedAt = max(task.updatedAt, now)
            return t
        }

        var t = task
        t.completedAt = now
        t.updatedAt = max(task.updatedAt, now)
        return t
    }

    public static func uncomplete(
        _ task: Task,
        now: Date
    ) -> Task {
        var t = task
        t.completedAt = nil
        t.updatedAt = max(task.updatedAt, now)
        return t
    }
}

