import Foundation

enum TaskTimeAdjustmentMapping {
    static func toDomain(_ record: TaskTimeAdjustmentRecord) -> TaskTimeAdjustment {
        TaskTimeAdjustment(
            id: record.id ?? UUID(),
            taskID: record.taskID ?? UUID(),
            durationSeconds: record.durationSeconds ?? 0,
            note: record.note,
            occurredAt: record.occurredAt ?? .distantPast,
            createdAt: record.createdAt ?? .distantPast,
            updatedAt: record.updatedAt ?? .distantPast
        )
    }

    static func apply(_ adjustment: TaskTimeAdjustment, to record: TaskTimeAdjustmentRecord) {
        record.id = adjustment.id
        record.taskID = adjustment.taskID
        record.durationSeconds = adjustment.durationSeconds
        record.note = adjustment.note
        record.occurredAt = adjustment.occurredAt
        record.createdAt = adjustment.createdAt
        record.updatedAt = adjustment.updatedAt
    }

    static func makeRecord(from adjustment: TaskTimeAdjustment) -> TaskTimeAdjustmentRecord {
        TaskTimeAdjustmentRecord(
            id: adjustment.id,
            taskID: adjustment.taskID,
            durationSeconds: adjustment.durationSeconds,
            note: adjustment.note,
            occurredAt: adjustment.occurredAt,
            createdAt: adjustment.createdAt,
            updatedAt: adjustment.updatedAt
        )
    }
}

enum TaskSessionExclusionMapping {
    static func toDomain(_ record: TaskSessionExclusionRecord) -> TaskSessionExclusion {
        TaskSessionExclusion(
            id: record.id ?? UUID(),
            taskID: record.taskID ?? UUID(),
            sessionID: record.sessionID ?? UUID(),
            createdAt: record.createdAt ?? .distantPast
        )
    }

    static func apply(_ exclusion: TaskSessionExclusion, to record: TaskSessionExclusionRecord) {
        record.id = exclusion.id
        record.taskID = exclusion.taskID
        record.sessionID = exclusion.sessionID
        record.createdAt = exclusion.createdAt
    }

    static func makeRecord(from exclusion: TaskSessionExclusion) -> TaskSessionExclusionRecord {
        TaskSessionExclusionRecord(
            id: exclusion.id,
            taskID: exclusion.taskID,
            sessionID: exclusion.sessionID,
            createdAt: exclusion.createdAt
        )
    }
}
