import Foundation
import ActivityKit

/// Shared between the iOS app and the widget extension.
/// Static attributes hold the session label; dynamic state holds only a fire date
/// (never remaining seconds — countdown is derived locally in the UI).
public struct TimerLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Wall-clock end of the running segment. Nil while paused with no countdown.
        public var fireDate: Date?
        public var isPaused: Bool

        public init(fireDate: Date?, isPaused: Bool) {
            self.fireDate = fireDate
            self.isPaused = isPaused
        }
    }

    public var title: String

    public init(title: String) {
        self.title = title
    }
}
