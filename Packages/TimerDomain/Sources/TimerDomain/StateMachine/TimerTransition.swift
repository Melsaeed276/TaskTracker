public enum TimerTransition: Sendable {
    public enum SessionState: Sendable, Hashable {
        case running
        case paused
        case stopped
        case reset
    }

    /// Applies an event kind to a per-session state machine.
    ///
    /// - Returns: The next state if the transition is valid; otherwise `nil` (stale/invalid).
    public static func nextState(
        from state: SessionState?,
        applying kind: TimerEventKind
    ) -> SessionState? {
        switch (state, kind) {
        case (nil, .started):
            return .running
        case (.running, .paused):
            return .paused
        case (.paused, .resumed):
            return .running
        case (.running, .stopped), (.paused, .stopped):
            return .stopped
        case (.running, .reset), (.paused, .reset), (.stopped, .reset):
            return .reset
        default:
            return nil
        }
    }
}

