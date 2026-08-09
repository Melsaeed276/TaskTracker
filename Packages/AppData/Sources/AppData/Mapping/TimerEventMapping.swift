import Foundation
import TimerDomain

public enum TimerEventMapping: Sendable {
    public static func toDomain(_ record: TimerEventRecord) -> TimerEvent {
        TimerEvent(
            id: record.id,
            sessionID: record.sessionID,
            kind: record.kind,
            occurredAt: record.occurredAt,
            deviceID: record.deviceID,
            lamport: record.lamport,
            schemaVersion: record.schemaVersion,
            duration: record.duration,
            relatedTaskID: record.relatedTaskID
        )
    }

    public static func apply(_ event: TimerEvent, to record: TimerEventRecord) {
        record.id = event.id
        record.sessionID = event.sessionID
        record.kind = event.kind
        record.occurredAt = event.occurredAt
        record.deviceID = event.deviceID
        record.lamport = event.lamport
        record.schemaVersion = event.schemaVersion
        record.duration = event.duration
        record.relatedTaskID = event.relatedTaskID
    }

    public static func makeRecord(from event: TimerEvent) -> TimerEventRecord {
        TimerEventRecord(
            id: event.id,
            sessionID: event.sessionID,
            kind: event.kind,
            occurredAt: event.occurredAt,
            deviceID: event.deviceID,
            lamport: event.lamport,
            schemaVersion: event.schemaVersion,
            duration: event.duration,
            relatedTaskID: event.relatedTaskID
        )
    }
}

