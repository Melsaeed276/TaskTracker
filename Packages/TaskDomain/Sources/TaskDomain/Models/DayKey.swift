import Foundation

public struct DayKey: Sendable, Hashable, Codable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension DayKey {
    static func from(date: Date, calendar: Calendar = Calendar.current) -> DayKey {
        var cal = calendar
        cal.locale = cal.locale ?? Locale(identifier: "en_US_POSIX")
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return DayKey(rawValue: String(format: "%04d-%02d-%02d", y, m, d))
    }
}

