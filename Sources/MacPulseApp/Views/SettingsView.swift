import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Form {
            Section("采样") {
                Picker("更新间隔", selection: $settings.updateInterval) {
                    Text("每 1 秒").tag(1.0)
                    Text("每 2 秒").tag(2.0)
                    Text("每 5 秒").tag(5.0)
                }
                Text("间隔越长越省电；历史图表仍按时间范围展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("菜单栏") {
                Picker("显示方式", selection: $settings.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) { display in
                        Text(display.label).tag(display)
                    }
                }
                if settings.menuBarDisplay == .graph {
                    Text("迷你图展示最近约 30 个采样点的 CPU 占用趋势。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("外观") {
                Picker("外观", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
            }

            Section("通用") {
                Toggle("开机启动", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
