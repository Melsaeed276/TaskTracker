public protocol TimerEventRepository: Sendable {
    func loadAllEvents() throws -> [TimerEvent]
    func append(_ event: TimerEvent) throws
}

