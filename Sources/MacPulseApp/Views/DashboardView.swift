import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MonitorStore

    private var metrics: MetricsSnapshot? { store.snapshot }

    var body: some View {
        let points = store.points(for: store.selectedRange)
        return NavigationStack(path: $store.navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    rangePicker
                    currentGrid
                    chartGrid(points)
                    footer
                }
                .padding(22)
            }
            .navigationDestination(for: MetricCategory.self) { category in
                MetricDetailView(category: category, store: store) {
                    guard !store.navigationPath.isEmpty else { return }
                    store.navigationPath.removeLast()
                }
            }
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
            Picker("时间范围", selection: $store.selectedRange) {
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
            Button {
                store.navigationPath.append(.cpu)
            } label: {
                CurrentMetricCard(
                    title: "CPU",
                    symbol: "cpu",
                    value: metrics.map { MetricsFormatter.cpuPercent($0.cpuPercent) } ?? "采集中",
                    detail: "总使用率",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("CPU详情")
            .accessibilityValue(MetricsFormatter.cpuPercent(metrics?.cpuPercent))

            Button {
                store.navigationPath.append(.memory)
            } label: {
                CurrentMetricCard(
                    title: "内存",
                    symbol: "memorychip",
                    value: metrics.map { MetricsFormatter.percent($0.memoryPercent) } ?? "采集中",
                    detail: memoryDetail,
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("内存详情")
            .accessibilityValue(memoryDetail)

            Button {
                store.navigationPath.append(.disk)
            } label: {
                CurrentMetricCard(
                    title: "磁盘读取",
                    symbol: "arrow.down.circle",
                    value: MetricsFormatter.bytesPerSecond(metrics?.diskReadBytesPerSecond),
                    detail: "写入 \(MetricsFormatter.bytesPerSecond(metrics?.diskWriteBytesPerSecond))",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("磁盘详情")
            .accessibilityValue(MetricsFormatter.bytesPerSecond(metrics?.diskReadBytesPerSecond))

            Button {
                store.navigationPath.append(.network)
            } label: {
                CurrentMetricCard(
                    title: "网络接收",
                    symbol: "arrow.down.circle",
                    value: MetricsFormatter.bytesPerSecond(metrics?.networkReceiveBytesPerSecond),
                    detail: "发送 \(MetricsFormatter.bytesPerSecond(metrics?.networkSendBytesPerSecond))",
                    tint: .green
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("网络详情")
            .accessibilityValue(MetricsFormatter.bytesPerSecond(metrics?.networkReceiveBytesPerSecond))
        }
    }

    private func chartGrid(_ points: [MetricPoint]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            HistoryChartCard(
                title: "处理器",
                symbol: "cpu",
                tint: .blue,
                points: points,
                metrics: [("使用率", \.cpu, MetricsFormatter.percent)],
                percentDomain: true
            )
            HistoryChartCard(
                title: "内存",
                symbol: "memorychip",
                tint: .purple,
                points: points,
                metrics: [("占用", \.memory, MetricsFormatter.percent)],
                percentDomain: true
            )
            HistoryChartCard(
                title: "磁盘 I/O",
                symbol: "internaldrive",
                tint: .orange,
                points: points,
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
                points: points,
                metrics: [
                    ("接收", \.networkReceive, MetricsFormatter.bytesPerSecond),
                    ("发送", \.networkSend, MetricsFormatter.bytesPerSecond)
                ],
                percentDomain: false
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前范围：\(store.selectedRange.label) · 历史分钟均值与本次运行明细 · 保留 7 天")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = store.historyError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var memoryDetail: String {
        guard let metrics,
              let used = metrics.memoryUsedBytes,
              let total = metrics.memoryTotalBytes else { return "物理内存" }
        return MetricsFormatter.memorySummary(usedBytes: used, totalBytes: total)
    }
}
