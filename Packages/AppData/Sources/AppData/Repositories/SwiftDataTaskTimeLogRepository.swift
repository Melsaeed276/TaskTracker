import Foundation
import SwiftData

@ModelActor
public actor SwiftDataTaskTimeLogRepository {}

extension SwiftDataTaskTimeLogRepository: TaskTimeLogRepository {
    public func adjustments(forTaskID taskID: UUID) async throws -> [TaskTimeAdjustment] {
        let fetch = FetchDescriptor<TaskTimeAdjustmentRecord>(
            predicate: #Predicate { $0.taskID == taskID }
        )
        return try modelContext.fetch(fetch).map(TaskTimeAdjustmentMapping.toDomain)
    }

    public func exclusions(forTaskID taskID: UUID) async throws -> [TaskSessionExclusion] {
        let fetch = FetchDescriptor<TaskSessionExclusionRecord>(
            predicate: #Predicate { $0.taskID == taskID }
        )
        return try modelContext.fetch(fetch).map(TaskSessionExclusionMapping.toDomain)
    }

    public func upsertAdjustment(_ adjustment: TaskTimeAdjustment) async throws {
        let id = adjustment.id
        let fetch = FetchDescriptor<TaskTimeAdjustmentRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(fetch).first {
            TaskTimeAdjustmentMapping.apply(adjustment, to: existing)
        } else {
            modelContext.insert(TaskTimeAdjustmentMapping.makeRecord(from: adjustment))
        }
        try modelContext.save()
    }

    public func deleteAdjustment(id: UUID) async throws {
        let fetch = FetchDescriptor<TaskTimeAdjustmentRecord>(
            predicate: #Predicate { $0.id == id }
        )
        for record in try modelContext.fetch(fetch) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    public func upsertExclusion(_ exclusion: TaskSessionExclusion) async throws {
        let taskID = exclusion.taskID
        let sessionID = exclusion.sessionID
        let fetch = FetchDescriptor<TaskSessionExclusionRecord>(
            predicate: #Predicate { $0.taskID == taskID && $0.sessionID == sessionID }
        )
        if let existing = try modelContext.fetch(fetch).first {
            TaskSessionExclusionMapping.apply(exclusion, to: existing)
        } else {
            modelContext.insert(TaskSessionExclusionMapping.makeRecord(from: exclusion))
        }
        try modelContext.save()
    }

    public func deleteExclusion(taskID: UUID, sessionID: UUID) async throws {
        let fetch = FetchDescriptor<TaskSessionExclusionRecord>(
            predicate: #Predicate { $0.taskID == taskID && $0.sessionID == sessionID }
        )
        for record in try modelContext.fetch(fetch) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
