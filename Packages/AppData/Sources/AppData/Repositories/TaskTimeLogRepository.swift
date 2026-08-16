import Foundation

public struct TaskTimeAdjustment: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var taskID: UUID
    public var durationSeconds: TimeInterval
    public var note: String?
    public var occurredAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        durationSeconds: TimeInterval,
        note: String? = nil,
        occurredAt: Date,
        createdAt: Date,
        updatedAt: Date
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

public struct TaskSessionExclusion: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var taskID: UUID
    public var sessionID: UUID
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        sessionID: UUID,
        createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.sessionID = sessionID
        self.createdAt = createdAt
    }
}

public protocol TaskTimeLogRepository: Sendable {
    func adjustments(forTaskID taskID: UUID) async throws -> [TaskTimeAdjustment]
    func exclusions(forTaskID taskID: UUID) async throws -> [TaskSessionExclusion]
    func upsertAdjustment(_ adjustment: TaskTimeAdjustment) async throws
    func deleteAdjustment(id: UUID) async throws
    func upsertExclusion(_ exclusion: TaskSessionExclusion) async throws
    func deleteExclusion(taskID: UUID, sessionID: UUID) async throws
}
