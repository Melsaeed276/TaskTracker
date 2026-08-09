import Foundation

public struct Task: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var notes: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var scheduledDay: DayKey?
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        notes: String? = nil,
        createdAt: Date,
        completedAt: Date? = nil,
        scheduledDay: DayKey? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledDay = scheduledDay
        self.updatedAt = updatedAt
    }

    public var isCompleted: Bool { completedAt != nil }
    public var isInPool: Bool { scheduledDay == nil && completedAt == nil }
}

