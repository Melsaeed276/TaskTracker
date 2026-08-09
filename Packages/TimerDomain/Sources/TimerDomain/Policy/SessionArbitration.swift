import Foundation

public struct SessionStart: Sendable, Hashable, Codable {
    public var sessionID: UUID
    public var startedAt: Date
    public var deviceID: UUID
    public var eventID: UUID

    public init(sessionID: UUID, startedAt: Date, deviceID: UUID, eventID: UUID) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.deviceID = deviceID
        self.eventID = eventID
    }
}

public enum SessionArbitration: Sendable {
    public static func startIndex(from events: [TimerEvent]) -> [SessionStart] {
        var bestBySession: [UUID: SessionStart] = [:]

        for event in events where event.kind == TimerEventKind.started.rawValue {
            let start = SessionStart(
                sessionID: event.sessionID,
                startedAt: event.occurredAt,
                deviceID: event.deviceID,
                eventID: event.id
            )

            if let existing = bestBySession[start.sessionID] {
                if compare(existing, start) == .orderedDescending {
                    bestBySession[start.sessionID] = start
                }
            } else {
                bestBySession[start.sessionID] = start
            }
        }

        return bestBySession.values.sorted(by: { compare($0, $1) == .orderedAscending })
    }

    public static func winningSession(from startIndex: [SessionStart]) -> SessionStart? {
        startIndex.last
    }

    public static func supersededAt(for sessionID: UUID, in startIndex: [SessionStart]) -> Date? {
        guard let idx = startIndex.firstIndex(where: { $0.sessionID == sessionID }) else { return nil }
        let nextIdx = startIndex.index(after: idx)
        guard nextIdx < startIndex.endIndex else { return nil }
        return startIndex[nextIdx].startedAt
    }

    private static func compare(_ a: SessionStart, _ b: SessionStart) -> ComparisonResult {
        if a.startedAt != b.startedAt { return a.startedAt < b.startedAt ? .orderedAscending : .orderedDescending }
        if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString ? .orderedAscending : .orderedDescending }
        if a.eventID != b.eventID { return a.eventID.uuidString < b.eventID.uuidString ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}

