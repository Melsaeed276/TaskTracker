public struct TimerEventKind: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension TimerEventKind {
    static let started = TimerEventKind(rawValue: "started")
    static let paused = TimerEventKind(rawValue: "paused")
    static let resumed = TimerEventKind(rawValue: "resumed")
    static let stopped = TimerEventKind(rawValue: "stopped")
    static let reset = TimerEventKind(rawValue: "reset")
}

