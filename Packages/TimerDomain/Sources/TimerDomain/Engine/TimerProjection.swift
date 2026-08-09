import Foundation

public struct SessionProjection: Sendable, Hashable {
    public var session: TimerSession?
    public var state: TimerTransition.SessionState?
    public var runningSince: Date?
    public var pausedSince: Date?

    public init(
        session: TimerSession?,
        state: TimerTransition.SessionState?,
        runningSince: Date?,
        pausedSince: Date?
    ) {
        self.session = session
        self.state = state
        self.runningSince = runningSince
        self.pausedSince = pausedSince
    }
}

public enum TimerProjection: Sendable {
    public static func project(
        events rawEvents: [TimerEvent],
        supersededAt: Date?,
        schema: TimerSchema = .v1
    ) -> SessionProjection {
        let events = dedupeByID(rawEvents)

        let quarantine = computeQuarantine(events: events, schema: schema)

        // We fold only kinds this build recognizes. Additional "known" kinds are treated as no-ops.
        // Unknown kinds remain skipped and contribute to quarantine.
        let foldableEvents = events
            .filter { schema.recognizes(kind: $0.kind) }
            .sorted(by: withinSessionSort)

        var startedAt: Date?
        var duration: TimeInterval = 0
        var relatedTaskID: UUID?

        var accumulatedActive: TimeInterval = 0
        var accumulatedPaused: TimeInterval = 0

        var state: TimerTransition.SessionState?
        var runningSince: Date?
        var pausedSince: Date?
        var terminalEvent: TimerTerminalEvent?

        for event in foldableEvents {
            let kind = event.kindValue

            if kind == .started {
                // Only the first start (in fold order) defines the session.
                if startedAt == nil {
                    startedAt = event.occurredAt
                    duration = event.duration ?? 0
                    relatedTaskID = event.relatedTaskID
                    state = .running
                    runningSince = event.occurredAt
                    pausedSince = nil
                    terminalEvent = nil
                    accumulatedActive = 0
                    accumulatedPaused = 0
                }
                continue
            }

            guard startedAt != nil else { continue }

            if let next = TimerTransition.nextState(from: state, applying: kind) {
                let t = event.occurredAt

                switch (state, next) {
                case (.running, .paused), (.running, .stopped), (.running, .reset):
                    if let from = runningSince {
                        accumulatedActive += max(0, t.timeIntervalSince(from))
                    }
                    runningSince = nil
                default:
                    break
                }

                switch (state, next) {
                case (.paused, .running), (.paused, .stopped), (.paused, .reset):
                    if let from = pausedSince {
                        accumulatedPaused += max(0, t.timeIntervalSince(from))
                    }
                    pausedSince = nil
                default:
                    break
                }

                state = next

                switch next {
                case .running:
                    runningSince = t
                case .paused:
                    pausedSince = t
                case .stopped:
                    terminalEvent = terminalEvent ?? .stopped(at: t)
                case .reset:
                    terminalEvent = terminalEvent ?? .reset(at: t)
                    // Reset discards history for this session.
                    accumulatedActive = 0
                    accumulatedPaused = 0
                    runningSince = nil
                    pausedSince = nil
                }
            }
        }

        guard let startedAt else {
            return SessionProjection(session: nil, state: nil, runningSince: nil, pausedSince: nil)
        }

        var session = TimerSession(
            id: foldableEvents.first?.sessionID ?? UUID(),
            startedAt: startedAt,
            duration: duration,
            relatedTaskID: relatedTaskID,
            accumulatedActive: accumulatedActive,
            accumulatedPaused: accumulatedPaused,
            quarantine: quarantine,
            supersededAt: supersededAt,
            terminalEvent: terminalEvent
        )

        // Apply supersession cutoff only if it happened before any user terminal event.
        if let cutoff = supersededAt {
            if terminalEvent == nil || terminalEvent!.occurredAt > cutoff {
                if let from = runningSince {
                    session.accumulatedActive += max(0, cutoff.timeIntervalSince(from))
                    runningSince = nil
                }
                if let from = pausedSince {
                    session.accumulatedPaused += max(0, cutoff.timeIntervalSince(from))
                    pausedSince = nil
                }
            }
        }

        return SessionProjection(session: session, state: state, runningSince: runningSince, pausedSince: pausedSince)
    }

    private static func computeQuarantine(events: [TimerEvent], schema: TimerSchema) -> TimerQuarantine {
        var unknownKinds = Set<String>()
        var newerSchema: Int? = nil

        for event in events {
            if !schema.recognizes(kind: event.kind) {
                unknownKinds.insert(event.kind)
            }
            if event.schemaVersion > schema.supportedSchemaVersion {
                newerSchema = max(newerSchema ?? 0, event.schemaVersion)
            }
        }

        return TimerQuarantine(
            unknownKinds: unknownKinds.sorted(),
            newerSchemaVersion: newerSchema
        )
    }

    private static func dedupeByID(_ events: [TimerEvent]) -> [TimerEvent] {
        let sorted = events.sorted(by: canonicalEventSort)
        var seen = Set<UUID>()
        var out: [TimerEvent] = []
        out.reserveCapacity(sorted.count)

        for e in sorted where !seen.contains(e.id) {
            seen.insert(e.id)
            out.append(e)
        }
        return out
    }

    private static func canonicalEventSort(_ a: TimerEvent, _ b: TimerEvent) -> Bool {
        if a.id != b.id { return a.id.uuidString < b.id.uuidString }
        if a.sessionID != b.sessionID { return a.sessionID.uuidString < b.sessionID.uuidString }
        if a.occurredAt != b.occurredAt { return a.occurredAt < b.occurredAt }
        if a.lamport != b.lamport { return a.lamport < b.lamport }
        if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString }
        if a.kind != b.kind { return a.kind < b.kind }
        if a.schemaVersion != b.schemaVersion { return a.schemaVersion < b.schemaVersion }
        let ad = a.duration ?? -1
        let bd = b.duration ?? -1
        if ad != bd { return ad < bd }
        let at = a.relatedTaskID?.uuidString ?? ""
        let bt = b.relatedTaskID?.uuidString ?? ""
        if at != bt { return at < bt }
        return false
    }

    private static func withinSessionSort(_ a: TimerEvent, _ b: TimerEvent) -> Bool {
        if a.lamport != b.lamport { return a.lamport < b.lamport }
        if a.occurredAt != b.occurredAt { return a.occurredAt < b.occurredAt }
        if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString }
        return a.id.uuidString < b.id.uuidString
    }
}

