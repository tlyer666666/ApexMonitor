import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Form {
            Section(L10n.Settings.sampling) {
                Picker(L10n.Settings.updateInterval, selection: $settings.updateInterval) {
                    Text(L10n.Settings.everySeconds(1)).tag(1.0)
                    Text(L10n.Settings.everySeconds(2)).tag(2.0)
                    Text(L10n.Settings.everySeconds(5)).tag(5.0)
                }
                Text(L10n.Settings.intervalNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.Settings.menuBar) {
                Picker(L10n.Settings.displayMode, selection: $settings.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) { display in
                        Text(display.label).tag(display)
                    }
                }
                if settings.menuBarDisplay == .graph {
                    Text(L10n.Settings.graphNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.Settings.appearance) {
                Picker(L10n.Settings.appearance, selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
            }

            Section(L10n.Settings.general) {
                Toggle(L10n.Settings.launchAtLogin, isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))

                Picker(L10n.Settings.language, selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                Text(L10n.Settings.languageNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
