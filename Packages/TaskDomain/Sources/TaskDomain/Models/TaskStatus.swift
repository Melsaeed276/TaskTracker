public enum TaskStatus: Sendable, Equatable {
    case pool
    case scheduled(DayKey)
    case completed
}

public extension Task {
    var status: TaskStatus {
        if completedAt != nil { return .completed }
        if let day = scheduledDay { return .scheduled(day) }
        return .pool
    }
}

