import Foundation

public enum TimerCalculator: Sendable {
    public static func elapsed(_ projection: SessionProjection, at: Date) -> TimeInterval {
        guard let session = projection.session else { return 0 }
        let runningExtra: TimeInterval
        if projection.state == .running, let since = projection.runningSince {
            runningExtra = max(0, at.timeIntervalSince(since))
        } else {
            runningExtra = 0
        }
        return max(0, session.accumulatedActive + runningExtra)
    }

    public static func remaining(_ projection: SessionProjection, at: Date) -> TimeInterval {
        guard let session = projection.session else { return 0 }
        return max(0, session.duration - elapsed(projection, at: at))
    }

    /// Remaining time for an already-evaluated active timer. Views must not compute this.
    public static func remaining(_ state: ActiveTimerState, at: Date) -> TimeInterval {
        switch state {
        case .idle, .completed:
            return 0
        case .active(let session, let phase):
            let runningExtra: TimeInterval
            if case .running(let since) = phase {
                runningExtra = max(0, at.timeIntervalSince(since))
            } else {
                runningExtra = 0
            }
            return max(0, session.duration - session.accumulatedActive - runningExtra)
        }
    }

    /// Global evaluation: what the app should show as the single active timer at this instant.
    ///
    /// Note: `.stopped` yields `.idle` globally (the timer is over and does not need an "awaiting
    /// acknowledgement" moment). `.expired` yields `.completed(.expired)` to support that moment.
    public static func evaluateActive(_ projection: SessionProjection, at: Date) -> ActiveTimerState {
        guard let session = projection.session else { return .idle }

        if case .reset? = session.terminalEvent {
            return .idle
        }
        if case .stopped? = session.terminalEvent {
            return .idle
        }
        if let supersededAt = session.supersededAt, shouldTreatAsSuperseded(session: session, at: supersededAt) {
            // A superseded session is never globally active.
            return .idle
        }

        if projection.state == .running {
            if remaining(projection, at: at) == 0 {
                return .completed(session, .expired)
            }
            if let since = projection.runningSince {
                return .active(session, .running(since: since))
            }
            return .active(session, .running(since: session.startedAt))
        }

        if projection.state == .paused {
            return .active(session, .paused)
        }

        return .idle
    }

    /// Session evaluation for history: how one specific session should be classified at an instant.
    public static func evaluateSession(_ projection: SessionProjection, at: Date) -> ActiveTimerState {
        guard let session = projection.session else { return .idle }

        if let supersededAt = session.supersededAt, shouldTreatAsSuperseded(session: session, at: supersededAt) {
            return .completed(session, .superseded)
        }

        if case .stopped? = session.terminalEvent {
            return .completed(session, .stoppedEarly)
        }

        if case .reset? = session.terminalEvent {
            return .idle
        }

        if projection.state == .running {
            if remaining(projection, at: at) == 0 {
                return .completed(session, .expired)
            }
            if let since = projection.runningSince {
                return .active(session, .running(since: since))
            }
            return .active(session, .running(since: session.startedAt))
        }

        if projection.state == .paused {
            return .active(session, .paused)
        }

        return .idle
    }

    private static func shouldTreatAsSuperseded(session: TimerSession, at supersededAt: Date) -> Bool {
        if let terminal = session.terminalEvent, terminal.occurredAt <= supersededAt {
            return false
        }
        return true
    }
}

