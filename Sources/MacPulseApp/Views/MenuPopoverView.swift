import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var loginItem: LoginItem
    let onOpenCategory: (MetricCategory) -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var metrics: MetricsSnapshot? { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacPulse")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(L10n.MenuBar.popoverSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 3)

            Divider()

            ForEach([MetricCategory.cpu, .memory, .disk, .network], id: \.self) { category in
                Button {
                    onOpenCategory(category)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        popoverRow(category)
                        MiniSparkline(
                            values: store.series(for: .fiveMinutes).points.map { $0[keyPath: category.pointKeyPath] },
                            tint: category.tint
                        )
                        .padding(.leading, 42)
                        .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Dashboard.detailNavigation(category.title))
                .accessibilityValue(rowValue(category))
            }

            Divider()

            Button {
                loginItem.setEnabled(!loginItem.isEnabled)
            } label: {
                Label(
                    loginItem.isEnabled ? L10n.MenuBar.launchAtLoginOn : L10n.MenuBar.launchAtLoginOff,
                    systemImage: loginItem.isEnabled ? "checkmark.circle.fill" : "powerplug"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(loginItem.isEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.MenuBar.launchAtLogin)
            .accessibilityValue(loginItem.isEnabled ? L10n.MenuBar.enabled : L10n.MenuBar.disabled)

            Button {
                onOpenSettings()
            } label: {
                Label(L10n.MenuBar.settings, systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)

            Button(action: onOpenDashboard) {
                Label(L10n.MenuBar.openDashboard, systemImage: "rectangle.expand.vertical")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 5)

            Button(action: onQuit) {
                Label(L10n.MenuBar.quit, systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial)
    }

    private func popoverRow(_ category: MetricCategory) -> some View {
        MetricRow(
            title: category.title,
            symbol: category.symbol,
            value: rowValue(category),
            detail: rowDetail(category),
            tint: category.tint,
            showsChevron: true
        )
    }

    private func rowValue(_ category: MetricCategory) -> String {
        switch category {
        case .cpu, .memory:
            return category.currentValue(metrics)
        case .disk:
            return "↓ \(MetricsFormatter.bytesPerSecond(metrics?.diskReadBytesPerSecond))  ↑ \(MetricsFormatter.bytesPerSecond(metrics?.diskWriteBytesPerSecond))"
        case .network:
            return "↓ \(MetricsFormatter.bytesPerSecond(metrics?.networkReceiveBytesPerSecond))  ↑ \(MetricsFormatter.bytesPerSecond(metrics?.networkSendBytesPerSecond))"
        }
    }

    private func rowDetail(_ category: MetricCategory) -> String {
        switch category {
        case .cpu:
            return metrics?.cpuPercent == nil ? L10n.MenuBar.waitingForFirstSample : L10n.MenuBar.trendSuffix
        case .memory:
            return memoryDetail
        case .disk:
            return L10n.MenuBar.readWrite
        case .network:
            return L10n.MenuBar.receiveSend
        }
    }

    private var memoryDetail: String {
        guard let metrics else { return L10n.Formatter.memoryFallback }
        return MetricsFormatter.memorySummary(usedBytes: metrics.memoryUsedBytes, totalBytes: metrics.memoryTotalBytes)
    }
}
