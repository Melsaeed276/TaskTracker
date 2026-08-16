import SwiftUI
import AppDesign

struct PreferencesView: View {
    var body: some View {
        Form {
            LabeledContent("App") {
                Text("TaskTracker")
            }
            LabeledContent("Version") {
                Text(versionString)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 120)
        .padding(AppSpacing.m)
        .accessibilityIdentifier("preferences.form")
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
