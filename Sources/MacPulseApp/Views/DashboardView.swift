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
                Text(L10n.Dashboard.title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text(L10n.Dashboard.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text(L10n.Dashboard.updating)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let updated = lastUpdateAge {
                    Text(updated)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(lastUpdateStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
                Text(L10n.Dashboard.localOnlyNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var lastUpdateAge: String? {
        guard let date = store.lastUpdateDate else { return nil }
        let age = Int(Date().timeIntervalSince(date))
        return age < 2 ? L10n.Dashboard.justUpdated : L10n.Dashboard.updatedAgo(age)
    }

    private var lastUpdateStale: Bool {
        guard let date = store.lastUpdateDate else { return false }
        return Date().timeIntervalSince(date) > 3
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.Dashboard.rangePicker, selection: $store.selectedRange) {
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
                .accessibilityLabel(L10n.Dashboard.detailNavigation(category.title))
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
            chartCard(.cpu, points: points, metric: (L10n.Charts.usage, \.cpu, MetricsFormatter.percent), secondary: nil)
            chartCard(.memory, points: points, metric: (L10n.Charts.occupancy, \.memory, MetricsFormatter.percent), secondary: nil)
            chartCard(.disk, points: points,
                      metric: (L10n.Details.read, \.diskRead, MetricsFormatter.bytesPerSecond),
                      secondary: (L10n.Details.write, \.diskWrite, MetricsFormatter.bytesPerSecond))
            chartCard(.network, points: points,
                      metric: (L10n.Details.receive, \.networkReceive, MetricsFormatter.bytesPerSecond),
                      secondary: (L10n.Details.send, \.networkSend, MetricsFormatter.bytesPerSecond))
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
            Text(String(format: L10n.Dashboard.footer, store.selectedRange.label))
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
              let total = metrics.memoryTotalBytes else { return L10n.Formatter.memoryFallback }
        return MetricsFormatter.memorySummary(usedBytes: used, totalBytes: total)
    }
}
