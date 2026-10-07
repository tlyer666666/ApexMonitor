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
                    Label(L10n.Details.backToOverview, systemImage: "chevron.left")
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
            Text(L10n.Details.processHeader).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(L10n.Details.memoryColumn).font(.caption).foregroundStyle(.secondary).frame(minWidth: 84, alignment: .trailing)
            Text(L10n.Details.cpuColumn).font(.caption).foregroundStyle(.secondary).frame(minWidth: 56, alignment: .trailing)
        }
    }
}

struct MemoryDetailView: View {
    @ObservedObject var store: MonitorStore

    private var snapshot: MetricsSnapshot? { store.snapshot }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                DetailCard(title: L10n.Details.memoryUsage) {
                    if let snapshot {
                        PercentBar(label: L10n.Charts.occupancy, percent: snapshot.memoryPercent, tint: .purple)
                        MetricRow(title: L10n.Details.used, symbol: "circle.fill", value: MetricsFormatter.bytes(snapshot.memoryUsedBytes), tint: .purple)
                        MetricRow(title: L10n.Details.available, symbol: "circle", value: availableBytes, tint: .purple)
                        MetricRow(title: L10n.Details.total, symbol: "memorychip", value: MetricsFormatter.bytes(snapshot.memoryTotalBytes), tint: .purple)
                    } else {
                        Text(L10n.Details.collecting)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: L10n.Details.topProcessesByMemory) {
                    if let summary = store.processSummary, !summary.topByMemory.isEmpty {
                        ProcessListHeader()
                        ForEach(Array(summary.topByMemory.enumerated()), id: \.element.pid) { index, stat in
                            ProcessListRow(rank: index + 1, stat: stat)
                        }
                        Text(L10n.Details.readableCount(summary.processCount))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(L10n.Details.collecting)
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
                DetailCard(title: L10n.Details.readSpeed) {
                    MetricRow(title: L10n.Details.read, symbol: "arrow.down.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.diskReadBytesPerSecond), tint: .orange)
                    MetricRow(title: L10n.Details.write, symbol: "arrow.up.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.diskWriteBytesPerSecond), tint: .orange)
                }

                DetailCard(title: L10n.Details.storage) {
                    if store.volumes.isEmpty {
                        Text(L10n.Details.collecting)
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
                                Text("\(L10n.Details.availableSpace) \(MetricsFormatter.bytes(volume.availableBytes as UInt64?))")
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
                DetailCard(title: L10n.Details.liveTraffic) {
                    MetricRow(title: L10n.Details.receive, symbol: "arrow.down.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.networkReceiveBytesPerSecond), tint: .green)
                    MetricRow(title: L10n.Details.send, symbol: "arrow.up.circle", value: MetricsFormatter.bytesPerSecond(snapshot?.networkSendBytesPerSecond), tint: .green)
                }

                DetailCard(title: L10n.Details.trafficStats) {
                    Picker(L10n.Details.statsWindow, selection: $store.trafficRange) {
                        ForEach(HistoryRange.allCases, id: \.self) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    let series = store.series(for: store.trafficRange)
                    let stats = HistoryAnalyzer.trafficStatistics(series.trafficPoints, sampleSpacing: series.spacing)
                    if stats.hasLegacyGaps {
                        Text(L10n.Details.legacyNote)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if stats.isEstimated {
                        Text(L10n.Details.estimatedNote)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    MetricRow(
                        title: L10n.Details.coverage,
                        symbol: "clock",
                        value: MetricsFormatter.duration(stats.coverageSeconds),
                        detail: L10n.Details.coverageNote,
                        tint: .green
                    )
                        MetricRow(
                            title: L10n.Details.receiveTotal,
                            symbol: "arrow.down.circle",
                            value: MetricsFormatter.bytes(stats.receivedBytes),
                            detail: stats.isEstimated
                                ? L10n.Details.peakEstimated(MetricsFormatter.bytesPerSecond(stats.receivePeakPerSecond))
                                : L10n.Details.peak(MetricsFormatter.bytesPerSecond(stats.receivePeakPerSecond)),
                            tint: .green
                        )
                        MetricRow(
                            title: L10n.Details.sendTotal,
                            symbol: "arrow.up.circle",
                            value: MetricsFormatter.bytes(stats.sentBytes),
                            detail: stats.isEstimated
                                ? L10n.Details.peakEstimated(MetricsFormatter.bytesPerSecond(stats.sendPeakPerSecond))
                                : L10n.Details.peak(MetricsFormatter.bytesPerSecond(stats.sendPeakPerSecond)),
                            tint: .green
                        )
                }

                DetailCard(title: L10n.Details.connectionStatus) {
                    if let status = store.pathStatus {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(status.online ? Color.green : Color.red)
                                .frame(width: 9, height: 9)
                            Text(status.online ? "\(L10n.Details.online) · \(status.interfaceType)" : L10n.Details.offline)
                                .font(.system(.body, design: .rounded).weight(.medium))
                        }
                    } else {
                        Text(L10n.Details.collecting)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: L10n.Details.interfaceDetails) {
                    if store.interfaces.isEmpty {
                        Text(L10n.Details.collecting)
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
                Text(interface.isConnected ? L10n.Details.connected : L10n.Details.disconnected)
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
                DetailCard(title: L10n.Details.cpuBreakdown) {
                    if let snapshot {
                        PercentBar(label: L10n.Details.user, percent: snapshot.cpuUserPercent, tint: .blue)
                        PercentBar(label: L10n.Details.system, percent: snapshot.cpuSystemPercent, tint: .blue)
                        PercentBar(label: L10n.Details.nice, percent: snapshot.cpuNicePercent, tint: .blue)
                        PercentBar(label: L10n.Details.idle, percent: snapshot.cpuIdlePercent, tint: .gray)
                    } else {
                        Text(L10n.Details.collecting)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: L10n.Details.loadAverage) {
                    if let load = store.loadAverage {
                        MetricRow(title: L10n.Details.minutes(1), symbol: "gauge", value: String(format: "%.2f", load.one), tint: .blue)
                        MetricRow(title: L10n.Details.minutes(5), symbol: "gauge", value: String(format: "%.2f", load.five), tint: .blue)
                        MetricRow(title: L10n.Details.minutes(15), symbol: "gauge", value: String(format: "%.2f", load.fifteen), tint: .blue)
                    } else {
                        Text(L10n.Details.collecting)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: L10n.Details.topProcessesByCPU) {
                    if let summary = store.processSummary, !summary.topByCPU.isEmpty {
                        ProcessListHeader()
                        ForEach(Array(summary.topByCPU.enumerated()), id: \.element.pid) { index, stat in
                            ProcessListRow(rank: index + 1, stat: stat)
                        }
                        Text(L10n.Details.readableCount(summary.processCount) + " · " + L10n.Details.singleCoreNote)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(L10n.Details.collecting)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

}
