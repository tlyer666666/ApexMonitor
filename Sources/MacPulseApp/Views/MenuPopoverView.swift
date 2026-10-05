import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var store: MonitorStore
    let onOpenCategory: (MetricCategory) -> Void
    let onOpenDashboard: () -> Void
    let onQuit: () -> Void

    private var metrics: MetricsSnapshot? { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacPulse")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("系统实时状态 · 点击分类查看详情")
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
                .accessibilityLabel("\(category.title)详情")
                .accessibilityValue(rowValue(category))
            }

            Divider()

            Button(action: onOpenDashboard) {
                Label("打开监控面板", systemImage: "rectangle.expand.vertical")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 5)

            Button(action: onQuit) {
                Label("退出 MacPulse", systemImage: "power")
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
            return metrics?.cpuPercent == nil ? "等待下一次有效采样" : "总使用率 · 最近 5 分钟"
        case .memory:
            return memoryDetail
        case .disk:
            return "读取 / 写入"
        case .network:
            return "接收 / 发送"
        }
    }

    private var memoryDetail: String {
        guard let metrics else { return "物理内存" }
        return MetricsFormatter.memorySummary(usedBytes: metrics.memoryUsedBytes, totalBytes: metrics.memoryTotalBytes)
    }
}
