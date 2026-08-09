import Foundation
import SwiftData
import TaskDomain

@ModelActor
public actor SwiftDataTaskRepository {}

extension SwiftDataTaskRepository: TaskRepository {
    public func task(id: UUID) async throws -> Task? {
        let fetch = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(fetch).first.map(TaskMapping.toDomain)
    }

    public func allTasks() async throws -> [Task] {
        let fetch = FetchDescriptor<TaskRecord>()
        return try modelContext.fetch(fetch).map(TaskMapping.toDomain)
    }

    public func poolTasks() async throws -> [Task] {
        let fetch = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.scheduledDay == nil && $0.completedAt == nil }
        )
        return try modelContext.fetch(fetch).map(TaskMapping.toDomain)
    }

    public func tasks(scheduledFor day: DayKey) async throws -> [Task] {
        let key = day.rawValue
        let fetch = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.scheduledDay == key && $0.completedAt == nil }
        )
        return try modelContext.fetch(fetch).map(TaskMapping.toDomain)
    }

    public func completedTasks() async throws -> [Task] {
        let fetch = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.completedAt != nil }
        )
        return try modelContext.fetch(fetch).map(TaskMapping.toDomain)
    }

    public func upsert(_ task: Task) async throws {
        let fetch = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let existing = try modelContext.fetch(fetch).first {
            TaskMapping.apply(task, to: existing)
        } else {
            modelContext.insert(TaskMapping.makeRecord(from: task))
        }
        try modelContext.save()
    }

    public func deleteTask(id: UUID) async throws {
        let fetch = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.id == id }
        )
        for record in try modelContext.fetch(fetch) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

