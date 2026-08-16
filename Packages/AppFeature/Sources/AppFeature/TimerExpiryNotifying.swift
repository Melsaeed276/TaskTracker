import Foundation

/// Schedules and cancels the local timer-expiry notification. AppFeature owns the when; the app
/// target supplies a `UNUserNotificationCenter`-backed implementation (or a no-op / spy in tests).
public protocol TimerExpiryNotifying: Sendable {
    func scheduleExpiry(at fireDate: Date) async
    func cancelExpiry() async
}

public struct NoOpTimerExpiryNotifier: TimerExpiryNotifying {
    public init() {}

    public func scheduleExpiry(at fireDate: Date) async {}

    public func cancelExpiry() async {}
}
