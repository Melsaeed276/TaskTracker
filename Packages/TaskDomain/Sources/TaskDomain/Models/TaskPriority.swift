import Foundation

/// User-facing task priority. Stored as an optional `Int` on `TaskRecord` for CloudKit.
public enum TaskPriority: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .none: return String(localized: "None")
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        }
    }
}
