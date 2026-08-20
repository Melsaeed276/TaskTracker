import SwiftUI
import AppDesign

struct PreferencesView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .auto
    @State private var selectedLanguage: AppLanguage = {
        let code = UserDefaults.standard.string(forKey: LanguagePreference.storageKey)
        return AppLanguage.allCases.first(where: { $0.languageCode == code }) ?? .system
    }()

    var body: some View {
        Form {
            LabeledContent("App") {
                Text("TaskTracker")
            }
            LabeledContent("Version") {
                Text(versionString)
            }

            Picker("Language", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .accessibilityIdentifier("preferences.languagePicker")
            .onChange(of: selectedLanguage) { _, newValue in
                LanguagePreference.shared.selectedLanguageCode = newValue.languageCode
                LanguagePreference.shared.apply()
            }

            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases, id: \.self) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .accessibilityIdentifier("preferences.appearancePicker")
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
#if DEBUG
#Preview("Preferences") {
    PreferencesView()
}
#endif
