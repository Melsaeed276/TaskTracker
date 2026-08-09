import Foundation

public enum TimerEngine: Sendable {
    public static func evaluateActiveTimer(
        events: [TimerEvent],
        at: Date,
        schema: TimerSchema = .v1
    ) -> ActiveTimerState {
        let index = SessionArbitration.startIndex(from: events)
        guard let winner = SessionArbitration.winningSession(from: index) else { return .idle }

        let supersededAt = SessionArbitration.supersededAt(for: winner.sessionID, in: index)
        let sessionEvents = events.filter { $0.sessionID == winner.sessionID }

        let projection = TimerProjection.project(
            events: sessionEvents,
            supersededAt: supersededAt,
            schema: schema
        )
        return TimerCalculator.evaluateActive(projection, at: at)
    }

    public static func projectSession(
        sessionID: UUID,
        from events: [TimerEvent],
        supersededAt: Date?,
        schema: TimerSchema = .v1
    ) -> SessionProjection {
        TimerProjection.project(
            events: events.filter { $0.sessionID == sessionID },
            supersededAt: supersededAt,
            schema: schema
        )
    }
}

