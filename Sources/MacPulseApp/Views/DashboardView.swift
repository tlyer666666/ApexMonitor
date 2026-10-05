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
                if let updated = lastUpdateAge {
                    Text(updated)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(lastUpdateStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
                Text("历史数据仅保存在本机")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var lastUpdateAge: String? {
        guard let date = store.lastUpdateDate else { return nil }
        let age = Int(Date().timeIntervalSince(date))
        return age < 2 ? "刚刚更新" : "最后更新 \(age) 秒前"
    }

    private var lastUpdateStale: Bool {
        guard let date = store.lastUpdateDate else { return false }
        return Date().timeIntervalSince(date) > 3
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
            ForEach([MetricCategory.cpu, .memory, .disk, .network], id: \.self) { category in
                Button {
                    store.navigationPath.append(category)
                } label: {
                    CurrentMetricCard(
                        title: category.title,
                        symbol: category.symbol,
                        value: category.currentValue(metrics),
                        detail: cardDetail(for: category),
                        tint: category.tint
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category.title)详情")
                .accessibilityValue(category.currentValue(metrics))
            }
        }
    }

    private func cardDetail(for category: MetricCategory) -> String {
        switch category {
        case .cpu:
            return category.headline
        case .memory:
            return memoryDetail
        case .disk:
            return "\(category.headline) \(MetricsFormatter.bytesPerSecond(metrics?.diskReadBytesPerSecond)) · \(category.secondaryHeadline ?? "") \(MetricsFormatter.bytesPerSecond(metrics?.diskWriteBytesPerSecond))"
        case .network:
            return "\(category.headline) \(MetricsFormatter.bytesPerSecond(metrics?.networkReceiveBytesPerSecond)) · \(category.secondaryHeadline ?? "") \(MetricsFormatter.bytesPerSecond(metrics?.networkSendBytesPerSecond))"
        }
    }

    private func chartGrid(_ points: [MetricPoint]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            chartCard(.cpu, points: points, metric: ("使用率", \.cpu, MetricsFormatter.percent), secondary: nil)
            chartCard(.memory, points: points, metric: ("占用", \.memory, MetricsFormatter.percent), secondary: nil)
            chartCard(.disk, points: points,
                      metric: ("读取", \.diskRead, MetricsFormatter.bytesPerSecond),
                      secondary: ("写入", \.diskWrite, MetricsFormatter.bytesPerSecond))
            chartCard(.network, points: points,
                      metric: ("接收", \.networkReceive, MetricsFormatter.bytesPerSecond),
                      secondary: ("发送", \.networkSend, MetricsFormatter.bytesPerSecond))
        }
    }

    private func chartCard(_ category: MetricCategory, points: [MetricPoint],
                           metric: (String, KeyPath<MetricPoint, Double?>, (Double?) -> String),
                           secondary: (String, KeyPath<MetricPoint, Double?>, (Double?) -> String)?) -> some View {
        HistoryChartCard(
            title: category.title,
            symbol: category.symbol,
            tint: category.tint,
            points: points,
            metrics: secondary.map { [metric, $0] } ?? [metric],
            percentDomain: category == .cpu || category == .memory
        )
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
