import Foundation

/// Deep links shared by the iOS app and the Live Activity widget extension.
enum TaskTrackerDeepLink {
    static let scheme = "tasktracker"
    static let timerHost = "timer"

    /// Opens the Timer tab. Used by Live Activity `widgetURL` / `Link`.
    static var timer: URL {
        // Force-unwrap is safe: scheme and host are compile-time constants.
        URL(string: "\(scheme)://\(timerHost)")!
    }

    static func isTimer(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == timerHost
    }
}
