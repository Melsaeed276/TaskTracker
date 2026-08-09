import Foundation
import SwiftData

@Model
public final class TaskRecord {
    // All properties are optional-or-defaulted to satisfy the CloudKit contract even before sync is enabled.
    // `id` is non-optional and acts as the application-level primary identifier.
    public var id: UUID
    public var title: String
    public var notes: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var scheduledDay: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        notes: String? = nil,
        createdAt: Date = Date.distantPast,
        completedAt: Date? = nil,
        scheduledDay: String? = nil,
        updatedAt: Date = Date.distantPast
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledDay = scheduledDay
        self.updatedAt = updatedAt
    }
}

