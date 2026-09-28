import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MonitorStore
    @State private var range: HistoryRange = .fifteenMinutes

    private var metrics: MetricsSnapshot? { store.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                rangePicker
                currentGrid
                chartGrid
                footer
            }
            .padding(22)
        }
        .frame(minWidth: 780, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("系统性能")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("MacPulse · 实时监控与历史统计")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("每秒更新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("历史数据仅保存在本机")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("时间范围", selection: $range) {
                ForEach(HistoryRange.allCases, id: \.self) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var currentGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            CurrentMetricCard(
                title: "CPU",
                symbol: "cpu",
                value: metrics.map { MetricsFormatter.cpuPercent($0.cpuPercent) } ?? "采集中",
                detail: "总使用率",
                tint: .blue
            )
            CurrentMetricCard(
                title: "内存",
                symbol: "memorychip",
                value: metrics.map { MetricsFormatter.percent($0.memoryPercent) } ?? "采集中",
                detail: memoryDetail,
                tint: .purple
            )
            CurrentMetricCard(
                title: "磁盘读取",
                symbol: "arrow.down.circle",
                value: MetricsFormatter.bytesPerSecond(metrics?.diskReadBytesPerSecond),
                detail: "写入 \(MetricsFormatter.bytesPerSecond(metrics?.diskWriteBytesPerSecond))",
                tint: .orange
            )
            CurrentMetricCard(
                title: "网络接收",
                symbol: "arrow.down.circle",
                value: MetricsFormatter.bytesPerSecond(metrics?.networkReceiveBytesPerSecond),
                detail: "发送 \(MetricsFormatter.bytesPerSecond(metrics?.networkSendBytesPerSecond))",
                tint: .green
            )
        }
    }

    private var chartGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            HistoryChartCard(
                title: "处理器",
                symbol: "cpu",
                tint: .blue,
                points: store.points(for: range),
                metrics: [("使用率", \.cpu, MetricsFormatter.percent)],
                percentDomain: true
            )
            HistoryChartCard(
                title: "内存",
                symbol: "memorychip",
                tint: .purple,
                points: store.points(for: range),
                metrics: [("占用", \.memory, MetricsFormatter.percent)],
                percentDomain: true
            )
            HistoryChartCard(
                title: "磁盘 I/O",
                symbol: "internaldrive",
                tint: .orange,
                points: store.points(for: range),
                metrics: [
                    ("读取", \.diskRead, MetricsFormatter.bytesPerSecond),
                    ("写入", \.diskWrite, MetricsFormatter.bytesPerSecond)
                ],
                percentDomain: false
            )
            HistoryChartCard(
                title: "网络",
                symbol: "network",
                tint: .green,
                points: store.points(for: range),
                metrics: [
                    ("接收", \.networkReceive, MetricsFormatter.bytesPerSecond),
                    ("发送", \.networkSend, MetricsFormatter.bytesPerSecond)
                ],
                percentDomain: false
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("当前范围：\(range.label) · 短周期显示逐秒明细，更长周期显示分钟级均值 · 历史保留 7 天")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var memoryDetail: String {
        guard let metrics,
              let used = metrics.memoryUsedBytes,
              let total = metrics.memoryTotalBytes else { return "物理内存" }
        return MetricsFormatter.memorySummary(usedBytes: used, totalBytes: total)
    }
}
