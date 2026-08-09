import Foundation

public enum ActiveTimerState: Sendable, Equatable {
    case idle
    case active(TimerSession, TimerPhase)
    case completed(TimerSession, CompletionReason)
}

public enum TimerPhase: Sendable, Equatable {
    case running(since: Date)
    case paused
}

public enum CompletionReason: Sendable, Equatable {
    case expired
    case stoppedEarly
    case superseded
}

