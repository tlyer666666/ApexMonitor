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

            Button {
                onOpenCategory(.cpu)
            } label: {
                MetricRow(
                    title: "CPU",
                    symbol: "cpu",
                    value: metrics.map { MetricsFormatter.cpuPercent($0.cpuPercent) } ?? "采集中",
                    detail: metrics?.cpuPercent == nil ? "等待下一次有效采样" : "总使用率 · 最近 5 分钟",
                    showsChevron: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MiniSparkline(values: store.points(for: .fiveMinutes).map(\.cpu))
                .padding(.bottom, 2)

            Button {
                onOpenCategory(.memory)
            } label: {
                MetricRow(
                    title: "内存",
                    symbol: "memorychip",
                    value: memoryValue,
                    detail: memoryDetail,
                    tint: .purple,
                    showsChevron: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onOpenCategory(.disk)
            } label: {
                MetricRow(
                    title: "磁盘",
                    symbol: "internaldrive",
                    value: "↓ \(MetricsFormatter.bytesPerSecond(metrics?.diskReadBytesPerSecond))  ↑ \(MetricsFormatter.bytesPerSecond(metrics?.diskWriteBytesPerSecond))",
                    detail: "读取 / 写入",
                    tint: .orange,
                    showsChevron: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onOpenCategory(.network)
            } label: {
                MetricRow(
                    title: "网络",
                    symbol: "network",
                    value: "↓ \(MetricsFormatter.bytesPerSecond(metrics?.networkReceiveBytesPerSecond))  ↑ \(MetricsFormatter.bytesPerSecond(metrics?.networkSendBytesPerSecond))",
                    detail: "接收 / 发送",
                    tint: .green,
                    showsChevron: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .frame(width: 330)
        .background(.regularMaterial)
    }

    private var memoryValue: String {
        guard let metrics else { return "采集中" }
        guard let percentage = metrics.memoryPercent else { return "—" }
        return "\(Int(percentage.rounded()))%"
    }

    private var memoryDetail: String {
        guard let metrics else { return "物理内存" }
        return MetricsFormatter.memorySummary(usedBytes: metrics.memoryUsedBytes, totalBytes: metrics.memoryTotalBytes)
    }
}
