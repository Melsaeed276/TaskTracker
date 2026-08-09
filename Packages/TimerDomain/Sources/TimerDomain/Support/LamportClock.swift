public struct LamportClock: Sendable, Hashable {
    public private(set) var value: Int

    public init(value: Int = 0) {
        self.value = value
    }

    public mutating func observe(remoteValue: Int) {
        value = max(value, remoteValue)
    }

    @discardableResult
    public mutating func tick() -> Int {
        value += 1
        return value
    }
}

