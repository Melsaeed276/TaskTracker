import Foundation
import SwiftData
import TaskDomain

public protocol AppDataTaskRepository: TaskRepository {
    func upsert(_ task: Task) throws
}

public actor SwiftDataTaskRepository: Sendable {
    private let actor: AppDataModelActor

    public init(modelContainer: ModelContainer) {
        self.actor = AppDataModelActor(modelContainer: modelContainer)
    }
}

extension SwiftDataTaskRepository: AppDataTaskRepository {
    public func task(id: UUID) throws -> Task? {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { $0.id == id }
            )
            return try actor.modelContext.fetch(fetch).first.map(TaskMapping.toDomain)
        }
    }

    public func allTasks() throws -> [Task] {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>()
            return try actor.modelContext.fetch(fetch).map(TaskMapping.toDomain)
        }
    }

    public func poolTasks() throws -> [Task] {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { $0.scheduledDay == nil && $0.completedAt == nil }
            )
            return try actor.modelContext.fetch(fetch).map(TaskMapping.toDomain)
        }
    }

    public func tasks(scheduledFor day: DayKey) throws -> [Task] {
        let key = day.rawValue
        return try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { $0.scheduledDay == key && $0.completedAt == nil }
            )
            return try actor.modelContext.fetch(fetch).map(TaskMapping.toDomain)
        }
    }

    public func completedTasks() throws -> [Task] {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { $0.completedAt != nil }
            )
            return try actor.modelContext.fetch(fetch).map(TaskMapping.toDomain)
        }
    }

    public func upsert(_ task: Task) throws {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { $0.id == task.id }
            )
            if let existing = try actor.modelContext.fetch(fetch).first {
                TaskMapping.apply(task, to: existing)
            } else {
                actor.modelContext.insert(TaskMapping.makeRecord(from: task))
            }
            try actor.modelContext.save()
        }
    }

    public func deleteTask(id: UUID) throws {
        try actor.modelContext.perform {
            let fetch = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { $0.id == id }
            )
            for record in try actor.modelContext.fetch(fetch) {
                actor.modelContext.delete(record)
            }
            try actor.modelContext.save()
        }
    }
}

