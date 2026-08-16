import Foundation
import TaskDomain

public enum TaskMapping: Sendable {
    public static func toDomain(_ record: TaskRecord) -> Task {
        Task(
            id: record.id ?? UUID(),
            title: record.title ?? "",
            notes: record.notes,
            createdAt: record.createdAt ?? .distantPast,
            completedAt: record.completedAt,
            scheduledDay: record.scheduledDay.map(DayKey.init(rawValue:)),
            priority: TaskPriority(rawValue: record.priority ?? 0) ?? .none,
            updatedAt: record.updatedAt ?? .distantPast
        )
    }

    public static func apply(_ task: Task, to record: TaskRecord) {
        record.id = task.id
        record.title = task.title
        record.notes = task.notes
        record.createdAt = task.createdAt
        record.completedAt = task.completedAt
        record.scheduledDay = task.scheduledDay?.rawValue
        record.priority = task.priority.rawValue
        record.updatedAt = task.updatedAt
    }

    public static func makeRecord(from task: Task) -> TaskRecord {
        TaskRecord(
            id: task.id,
            title: task.title,
            notes: task.notes,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            scheduledDay: task.scheduledDay?.rawValue,
            priority: task.priority.rawValue,
            updatedAt: task.updatedAt
        )
    }
}
