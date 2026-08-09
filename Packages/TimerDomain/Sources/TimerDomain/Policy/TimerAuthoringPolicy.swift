public enum TimerAuthoringPolicy: Sendable {
    public static func isAuthorable(_ kind: TimerEventKind, quarantined: Bool) -> Bool {
        guard quarantined else { return true }
        return kind == .started || kind == .stopped
    }
}

