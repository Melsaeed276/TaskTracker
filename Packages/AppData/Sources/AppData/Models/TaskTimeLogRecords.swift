import Foundation
import SwiftData

@Model
public final class TaskTimeAdjustmentRecord {
    public var id: UUID?
    public var taskID: UUID?
    /// Stored seconds; coalesces to 0 when nil.
    public var durationSeconds: Double?
    public var note: String?
    public var occurredAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: UUID = UUID(),
        taskID: UUID = UUID(),
        durationSeconds: Double = 0,
        note: String? = nil,
        occurredAt: Date = Date.distantPast,
        createdAt: Date = Date.distantPast,
        updatedAt: Date = Date.distantPast
    ) {
        self.id = id
        self.taskID = taskID
        self.durationSeconds = durationSeconds
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class TaskSessionExclusionRecord {
    public var id: UUID?
    public var taskID: UUID?
    public var sessionID: UUID?
    public var createdAt: Date?

    public init(
        id: UUID = UUID(),
        taskID: UUID = UUID(),
        sessionID: UUID = UUID(),
        createdAt: Date = Date.distantPast
    ) {
        self.id = id
        self.taskID = taskID
        self.sessionID = sessionID
        self.createdAt = createdAt
    }
}
