import Foundation

/// App-layer seam for Live Activities. Implementations live only in the iOS app target
/// (ActivityKit). Package tests use `NoOpTimerLiveActivityController`.
///
/// Contract: pass a **fire date** (wall clock), never remaining/elapsed seconds.
/// The system countdown UI derives display time locally from that date.
public protocol TimerLiveActivityControlling: Sendable {
    /// When `fireDate` is non-nil, start or update the Live Activity.
    /// When `fireDate` is nil, end any active Live Activity.
    func sync(title: String, fireDate: Date?, isPaused: Bool) async
}

public struct NoOpTimerLiveActivityController: TimerLiveActivityControlling {
    public init() {}

    public func sync(title: String, fireDate: Date?, isPaused: Bool) async {}
}
