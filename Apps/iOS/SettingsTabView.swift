import SwiftUI
import AppDesign
import UserNotifications

struct SettingsTabView: View {
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section("App") {
                    LabeledContent("Name") {
                        Text("TaskTracker")
                    }
                    LabeledContent("Version") {
                        Text(versionString)
                    }
                }

                Section("Notifications") {
                    LabeledContent("Timer expiry") {
                        Text(statusLabel)
                            .foregroundStyle(.secondary)
                    }
                    if authorizationStatus == .notDetermined || authorizationStatus == .denied {
                        Button("Enable Notifications") {
                            Task { await requestAuthorization() }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await refreshStatus() }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var statusLabel: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
    }
}
