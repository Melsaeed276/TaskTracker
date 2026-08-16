import ActivityKit
import Foundation
import OSLog
import AppFeature

/// iOS ActivityKit adapter. Starts/updates/ends a single timer Live Activity from fire dates.
/// Live Activities are iOS/iPadOS only — macOS has no ActivityKit surface.
struct ActivityKitTimerLiveActivityController: TimerLiveActivityControlling {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TaskTracker",
        category: "LiveActivity"
    )

    func sync(title: String, fireDate: Date?, isPaused: Bool) async {
        let auth = ActivityAuthorizationInfo()
        guard auth.areActivitiesEnabled else {
            Self.log.notice("Live Activities disabled in system/app settings — skipping sync")
            return
        }

        if let fireDate {
            let state = TimerLiveActivityAttributes.ContentState(
                fireDate: isPaused ? nil : fireDate,
                isPaused: isPaused
            )
            let content = ActivityContent(state: state, staleDate: isPaused ? nil : fireDate)

            if let existing = Activity<TimerLiveActivityAttributes>.activities.first {
                await existing.update(content)
                Self.log.debug("Updated Live Activity title=\(title, privacy: .public) paused=\(isPaused)")
            } else {
                do {
                    let attributes = TimerLiveActivityAttributes(title: title)
                    _ = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                    Self.log.debug("Started Live Activity title=\(title, privacy: .public)")
                } catch {
                    Self.log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            for activity in Activity<TimerLiveActivityAttributes>.activities {
                let final = TimerLiveActivityAttributes.ContentState(fireDate: nil, isPaused: false)
                await activity.end(
                    ActivityContent(state: final, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            Self.log.debug("Ended Live Activity")
        }
    }
}
