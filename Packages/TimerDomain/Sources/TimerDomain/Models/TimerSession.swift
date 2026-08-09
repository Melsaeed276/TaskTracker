import Foundation

public struct TimerQuarantine: Sendable, Hashable, Codable {
    public var unknownKinds: [String]
    public var newerSchemaVersion: Int?

    public init(unknownKinds: [String] = [], newerSchemaVersion: Int? = nil) {
        self.unknownKinds = unknownKinds
        self.newerSchemaVersion = newerSchemaVersion
    }

    public var isQuarantined: Bool {
        !unknownKinds.isEmpty || newerSchemaVersion != nil
    }
}

public enum TimerTerminalEvent: Sendable, Hashable, Codable {
    case stopped(at: Date)
    case reset(at: Date)

    public var occurredAt: Date {
        switch self {
        case .stopped(let at), .reset(let at): at
        }
    }
}

public struct TimerSession: Sendable, Hashable, Codable {
    public var id: UUID
    public var startedAt: Date
    public var duration: TimeInterval
    public var relatedTaskID: UUID?

    /// Active time accumulated from the log, excluding any currently-running segment.
    public var accumulatedActive: TimeInterval

    /// Paused time accumulated from the log.
    public var accumulatedPaused: TimeInterval

    /// The per-session quarantine predicate, derived from the session's events.
    public var quarantine: TimerQuarantine

    /// If non-nil, this session was superseded at the given instant (derived from the successor's start).
    public var supersededAt: Date?

    /// User-authored terminal action, if any.
    public var terminalEvent: TimerTerminalEvent?

    public init(
        id: UUID,
        startedAt: Date,
        duration: TimeInterval,
        relatedTaskID: UUID? = nil,
        accumulatedActive: TimeInterval,
        accumulatedPaused: TimeInterval,
        quarantine: TimerQuarantine = TimerQuarantine(),
        supersededAt: Date? = nil,
        terminalEvent: TimerTerminalEvent? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.relatedTaskID = relatedTaskID
        self.accumulatedActive = accumulatedActive
        self.accumulatedPaused = accumulatedPaused
        self.quarantine = quarantine
        self.supersededAt = supersededAt
        self.terminalEvent = terminalEvent
    }
}

