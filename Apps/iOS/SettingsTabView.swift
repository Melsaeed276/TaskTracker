import SwiftUI
import UIKit
import AppDesign
import UserNotifications

struct SettingsTabView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .auto
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

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text("Change Language…")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .accessibilityIdentifier("settings.openLanguage")

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearancePreference.allCases, id: \.self) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.appearancePicker")
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
            return String(localized: "Allowed")
        case .denied:
            return String(localized: "Denied")
        case .notDetermined:
            return String(localized: "Not requested")
        @unknown default:
            return String(localized: "Unknown")
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
#if DEBUG
#Preview("Settings") {
    SettingsTabView()
}
#endif
