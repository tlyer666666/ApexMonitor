import SwiftUI

struct MetricDetailView: View {
    let category: MetricCategory
    @ObservedObject var store: MonitorStore
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    onBack()
                } label: {
                    Label("返回总览", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                switch category {
                case .cpu:
                    CPUDetailView(store: store)
                case .memory:
                    MemoryDetailView(store: store)
                case .disk:
                    DiskDetailView(store: store)
                case .network:
                    NetworkDetailView(store: store)
                }
            }
            .padding(20)
        }
        .navigationTitle(category.title)
        .onAppear { store.beginLiveDetail(category) }
        .onDisappear { store.endLiveDetail(category) }
    }
}

struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PercentBar: View {
    let label: String
    let percent: Double?
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .frame(minWidth: 56, alignment: .leading)
            if let percent, percent.isFinite {
                ProgressView(value: min(max(percent, 0), 100) / 100)
                    .tint(tint)
                Text(MetricsFormatter.percent(percent))
                    .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                    .frame(minWidth: 56, alignment: .trailing)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

struct ProcessListRow: View {
    let rank: Int
    let stat: ProcessStat

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 18, alignment: .leading)
            Text(stat.name)
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 12)
            Text(MetricsFormatter.bytes(stat.residentBytes))
                .font(.system(.callout, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 84, alignment: .trailing)
            Text(MetricsFormatter.percent(stat.cpuPercent))
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

struct ProcessListHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("#").frame(minWidth: 18, alignment: .leading)
            Text("进程").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text("内存").font(.caption).foregroundStyle(.secondary).frame(minWidth: 84, alignment: .trailing)
            Text("CPU").font(.caption).foregroundStyle(.secondary).frame(minWidth: 56, alignment: .trailing)
        }
    }
}

struct MemoryDetailView: View {
    @ObservedObject var store: MonitorStore

    private var snapshot: MetricsSnapshot? { store.snapshot }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                DetailCard(title: "内存用量") {
                    if let snapshot {
                        PercentBar(label: "占用", percent: snapshot.memoryPercent, tint: .purple)
                        MetricRow(title: "已用", symbol: "circle.fill", value: MetricsFormatter.bytes(snapshot.memoryUsedBytes), tint: .purple)
                        MetricRow(title: "可用", symbol: "circle", value: availableBytes, tint: .purple)
                        MetricRow(title: "总量", symbol: "memorychip", value: MetricsFormatter.bytes(snapshot.memoryTotalBytes), tint: .purple)
                    } else {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: "进程占用 · Top 10（按内存）") {
                    if let summary = store.processSummary, !summary.topByMemory.isEmpty {
                        ProcessListHeader()
                        ForEach(Array(summary.topByMemory.enumerated()), id: \.element.pid) { index, stat in
                            ProcessListRow(rank: index + 1, stat: stat)
                        }
                        Text("当前权限可读 \(summary.processCount) 个进程")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private var availableBytes: String {
        guard let snapshot,
              let used = snapshot.memoryUsedBytes,
              let total = snapshot.memoryTotalBytes,
              total >= used else { return "—" }
        return MetricsFormatter.bytes(total - used)
    }

}

struct DiskDetailView: View {
    @ObservedObject var store: MonitorStore

    private var snapshot: MetricsSnapshot? { store.snapshot }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                DetailCard(title: "读写速度") {
                    MetricRow(title: "读取", symbol: "arrow.down.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.diskReadBytesPerSecond), tint: .orange)
                    MetricRow(title: "写入", symbol: "arrow.up.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.diskWriteBytesPerSecond), tint: .orange)
                }

                DetailCard(title: "存储空间") {
                    if store.volumes.isEmpty {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.volumes) { volume in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(volume.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(MetricsFormatter.bytes(volume.usedBytes)) / \(MetricsFormatter.bytes(volume.totalBytes))")
                                        .font(.system(.caption, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                if volume.totalBytes > 0 {
                                    ProgressView(value: Double(volume.usedBytes) / Double(volume.totalBytes))
                                        .tint(.orange)
                                }
                                Text("可用 \(MetricsFormatter.bytes(volume.availableBytes as UInt64?))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
        }
    }
}

struct NetworkDetailView: View {
    @ObservedObject var store: MonitorStore

    private var snapshot: MetricsSnapshot? { store.snapshot }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                DetailCard(title: "实时流量") {
                    MetricRow(title: "接收", symbol: "arrow.down.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.networkReceiveBytesPerSecond), tint: .green)
                    MetricRow(title: "发送", symbol: "arrow.up.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.networkSendBytesPerSecond), tint: .green)
                }

                DetailCard(title: "流量统计") {
                    Picker("统计时段", selection: $store.trafficRange) {
                        ForEach(HistoryRange.allCases, id: \.self) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    let series = store.series(for: store.trafficRange)
                    let stats = HistoryAnalyzer.trafficStatistics(series.trafficPoints, sampleSpacing: series.spacing)
                    if stats.hasLegacyGaps {
                        Text("旧版历史缺少有效时长，以下总量仅包含可核算的新样本；旧数据未删除。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if stats.isEstimated {
                        Text("部分历史或边界分钟的总量、峰值为估算；未知时长不补齐。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    MetricRow(
                        title: "统计覆盖",
                        symbol: "clock",
                        value: MetricsFormatter.duration(stats.coverageSeconds),
                        detail: "按有效采样时长累计；不补齐未监测时段",
                        tint: .green
                    )
                        MetricRow(
                            title: "接收总量",
                            symbol: "arrow.down.circle",
                            value: MetricsFormatter.bytes(stats.receivedBytes),
                            detail: stats.isEstimated
                                ? "峰值≈ \(MetricsFormatter.bytesPerSecond(stats.receivePeakPerSecond))"
                                : "峰值 \(MetricsFormatter.bytesPerSecond(stats.receivePeakPerSecond))",
                            tint: .green
                        )
                        MetricRow(
                            title: "发送总量",
                            symbol: "arrow.up.circle",
                            value: MetricsFormatter.bytes(stats.sentBytes),
                            detail: stats.isEstimated
                                ? "峰值≈ \(MetricsFormatter.bytesPerSecond(stats.sendPeakPerSecond))"
                                : "峰值 \(MetricsFormatter.bytesPerSecond(stats.sendPeakPerSecond))",
                            tint: .green
                        )
                }

                DetailCard(title: "连接状态") {
                    if let status = store.pathStatus {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(status.online ? Color.green : Color.red)
                                .frame(width: 9, height: 9)
                            Text(status.online ? "在线 · \(status.interfaceType)" : "离线")
                                .font(.system(.body, design: .rounded).weight(.medium))
                        }
                    } else {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: "接口明细") {
                    if store.interfaces.isEmpty {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.interfaces) { interface in
                            InterfaceRow(
                                interface: interface,
                                runtime: store.interfaceRuntimeTotals[interface.name]
                            )
                        }
                    }
                }
        }
    }
}

struct InterfaceRow: View {
    let interface: InterfaceDetail
    let runtime: NetworkInterfaceCounters?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(interface.isConnected ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(interface.name)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text(interface.isConnected ? "已连接" : "未连接")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let runtime {
                    Text("↓ \(MetricsFormatter.bytes(runtime.receivedBytes)) ↑ \(MetricsFormatter.bytes(runtime.sentBytes))")
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            let addresses = (interface.ipv4 + interface.ipv6).joined(separator: " · ")
            if !addresses.isEmpty {
                Text(addresses)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CPUDetailView: View {
    @ObservedObject var store: MonitorStore

    private var snapshot: MetricsSnapshot? { store.snapshot }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                DetailCard(title: "处理器分解") {
                    if let snapshot {
                        PercentBar(label: "用户", percent: snapshot.cpuUserPercent, tint: .blue)
                        PercentBar(label: "系统", percent: snapshot.cpuSystemPercent, tint: .blue)
                        PercentBar(label: "友好", percent: snapshot.cpuNicePercent, tint: .blue)
                        PercentBar(label: "空闲", percent: snapshot.cpuIdlePercent, tint: .gray)
                    } else {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: "负载均值") {
                    if let load = store.loadAverage {
                        MetricRow(title: "1 分钟", symbol: "gauge", value: String(format: "%.2f", load.one), tint: .blue)
                        MetricRow(title: "5 分钟", symbol: "gauge", value: String(format: "%.2f", load.five), tint: .blue)
                        MetricRow(title: "15 分钟", symbol: "gauge", value: String(format: "%.2f", load.fifteen), tint: .blue)
                    } else {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: "进程占用 · Top 10（按 CPU）") {
                    if let summary = store.processSummary, !summary.topByCPU.isEmpty {
                        ProcessListHeader()
                        ForEach(Array(summary.topByCPU.enumerated()), id: \.element.pid) { index, stat in
                            ProcessListRow(rank: index + 1, stat: stat)
                        }
                        Text("当前权限可读 \(summary.processCount) 个进程 · CPU% 以单核 100% 为基准")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("采集中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

}
