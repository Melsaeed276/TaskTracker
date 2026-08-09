public struct TimerSchema: Sendable, Hashable, Codable {
    public var supportedSchemaVersion: Int
    public var knownKinds: Set<String>

    public init(supportedSchemaVersion: Int, knownKinds: Set<String>) {
        self.supportedSchemaVersion = supportedSchemaVersion
        self.knownKinds = knownKinds
    }

    public func recognizes(kind: String) -> Bool {
        knownKinds.contains(kind)
    }

    public static let v1 = TimerSchema(
        supportedSchemaVersion: 1,
        knownKinds: [
            TimerEventKind.started.rawValue,
            TimerEventKind.paused.rawValue,
            TimerEventKind.resumed.rawValue,
            TimerEventKind.stopped.rawValue,
            TimerEventKind.reset.rawValue,
        ]
    )
}

