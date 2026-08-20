import UserNotifications
import Foundation
import AppFeature

/// macOS-only `UNUserNotificationCenter` adapter, the counterpart to the iOS one. Kept out of
/// AppFeature so the package never links notification APIs.
struct UserNotificationsTimerExpiryNotifier: TimerExpiryNotifying {
    static let requestIdentifier = "com.diwan.TaskTracker.timerExpiry"

    func scheduleExpiry(at fireDate: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        await cancelExpiry()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Timer finished")
        content.body = String(localized: "Your focus session is done.")
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancelExpiry() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
    }
}
