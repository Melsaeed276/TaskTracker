import Foundation

public struct TimerEvent: Sendable, Hashable, Codable {
    public var id: UUID
    public var sessionID: UUID
    public var kind: String
    public var occurredAt: Date
    public var deviceID: UUID
    public var lamport: Int
    public var schemaVersion: Int
    public var duration: TimeInterval?
    public var relatedTaskID: UUID?

    public init(
        id: UUID,
        sessionID: UUID,
        kind: String,
        occurredAt: Date,
        deviceID: UUID,
        lamport: Int,
        schemaVersion: Int,
        duration: TimeInterval? = nil,
        relatedTaskID: UUID? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.occurredAt = occurredAt
        self.deviceID = deviceID
        self.lamport = lamport
        self.schemaVersion = schemaVersion
        self.duration = duration
        self.relatedTaskID = relatedTaskID
    }
}

public extension TimerEvent {
    var kindValue: TimerEventKind { TimerEventKind(rawValue: kind) }
}

