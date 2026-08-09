public protocol TimerEventRepository: Sendable {
    func loadAllEvents() async throws -> [TimerEvent]
    func append(_ event: TimerEvent) async throws
}

