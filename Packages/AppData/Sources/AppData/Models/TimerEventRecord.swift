import Foundation
import SwiftData

@Model
public final class TimerEventRecord {
    // SwiftData's CloudKit validation only recognizes true Optionality, not a Swift init-parameter
    // default — a non-optional stored property fails the mirroring contract even with `= value` in
    // init. Every property is therefore Optional here; TimerEventMapping coalesces to the same
    // defaults shown below when reading into the non-optional domain `TimerEvent`.
    public var id: UUID?
    public var sessionID: UUID?
    public var kind: String?
    public var occurredAt: Date?
    public var deviceID: UUID?
    public var lamport: Int?
    public var schemaVersion: Int?
    public var duration: Double?
    public var relatedTaskID: UUID?

    public init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        kind: String = "",
        occurredAt: Date = Date.distantPast,
        deviceID: UUID = UUID(),
        lamport: Int = 0,
        schemaVersion: Int = 0,
        duration: Double? = nil,
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

extension TimerEventRecord {
    public static var q1StartIndexSort: [SortDescriptor<TimerEventRecord>] {
        [
            SortDescriptor(\.occurredAt, order: .forward),
            SortDescriptor(\.deviceID, order: .forward),
        ]
    }
}

