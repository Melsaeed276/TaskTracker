import Foundation
import SwiftData

@Model
public final class TaskRecord {
    // SwiftData's CloudKit validation only recognizes true Optionality, not a Swift init-parameter
    // default — a non-optional stored property fails the mirroring contract even with `= value` in
    // init. Every property is therefore Optional here; TaskMapping coalesces to the same defaults
    // shown below when reading into the non-optional domain `Task`.
    public var id: UUID?
    public var title: String?
    public var notes: String?
    public var createdAt: Date?
    public var completedAt: Date?
    public var scheduledDay: String?
    /// Raw `TaskPriority.rawValue`. `nil` coalesces to `.none` in mapping.
    public var priority: Int?
    public var updatedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String = "",
        notes: String? = nil,
        createdAt: Date = Date.distantPast,
        completedAt: Date? = nil,
        scheduledDay: String? = nil,
        priority: Int? = nil,
        updatedAt: Date = Date.distantPast
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledDay = scheduledDay
        self.priority = priority
        self.updatedAt = updatedAt
    }
}
