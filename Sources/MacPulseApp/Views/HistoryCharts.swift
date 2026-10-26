import SwiftUI

struct SeriesChart: View {
    struct Series {
        let dates: [Date]
        let values: [Double?]
        var opacity: Double = 0.9
        var fillsArea: Bool = true
    }

    let series: [Series]
    let tint: Color
    let percentDomain: Bool

    var body: some View {
        Canvas { context, size in
            let resolved = series.map { input in
                HistoryAnalyzer.downsampleIndices(count: input.values.count, maxPoints: 600)
                    .map { index -> (date: Date, value: Double?) in
                        let raw = input.values[index]
                        let cleaned = raw.flatMap { $0.isFinite ? max($0, 0) : nil }
                        return (input.dates[index], cleaned)
                    }
            }
            guard resolved.contains(where: { !$0.isEmpty }) else { return }
            let maxValue = domainMax(from: resolved)
            let span = timeSpan(of: resolved)

            for index in 0..<3 {
                let y = size.height * CGFloat(index) / 2
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.primary.opacity(0.07)), lineWidth: 1)
            }

            for (seriesIndex, points) in resolved.enumerated() {
                let style = series[seriesIndex]
                var run: [(x: CGFloat, y: CGFloat)] = []
                for point in points {
                    if let value = point.value {
                        let x = xPosition(for: point.date, span: span, width: size.width)
                        let ratio = min(max(value / maxValue, 0), 1)
                        run.append((x, size.height * (1 - CGFloat(ratio))))
                    } else if !run.isEmpty {
                        strokeRun(run, in: &context, size: size,
                                  opacity: style.opacity, fillsArea: style.fillsArea && seriesIndex == 0)
                        run = []
                    }
                }
                if !run.isEmpty {
                    strokeRun(run, in: &context, size: size,
                              opacity: style.opacity, fillsArea: style.fillsArea && seriesIndex == 0)
                }
            }
        }
    }

    private func strokeRun(_ run: [(x: CGFloat, y: CGFloat)], in context: inout GraphicsContext,
                           size: CGSize, opacity: Double, fillsArea: Bool) {
        guard let first = run.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in run.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.stroke(
            path,
            with: .color(tint.opacity(opacity)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        guard fillsArea else { return }
        var area = path
        area.addLine(to: CGPoint(x: run.last!.x, y: size.height))
        area.addLine(to: CGPoint(x: first.x, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .color(tint.opacity(0.10)))
    }

    private func timeSpan(of resolved: [[(date: Date, value: Double?)]]) -> (start: Date, end: Date)? {
        let dates = resolved.flatMap { $0.map(\.date) }
        guard let start = dates.min(), let end = dates.max() else { return nil }
        return (start, end)
    }

    /// X positions follow real time so mixed minute/second resolutions and
    /// changed sampling cadences keep their true spacing.
    private func xPosition(for date: Date, span: (start: Date, end: Date)?, width: CGFloat) -> CGFloat {
        guard let span, span.end.timeIntervalSince(span.start) > 0 else { return width / 2 }
        let fraction = date.timeIntervalSince(span.start) / span.end.timeIntervalSince(span.start)
        return width * CGFloat(min(max(fraction, 0), 1))
    }

    private func domainMax(from resolved: [[(date: Date, value: Double?)]]) -> Double {
        if percentDomain { return 100 }
        let peak = resolved.flatMap { $0.compactMap(\.value) }.max() ?? 1
        return max(peak * 1.15, 1)
    }
}

struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

struct HistoryChartCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let points: [MetricPoint]
    let metrics: [(name: String, keyPath: KeyPath<MetricPoint, Double?>, formatter: (Double?) -> String)]
    let percentDomain: Bool

    var body: some View {
        let stats = metrics.map { HistoryAnalyzer.statistics(points, metric: $0.keyPath) }
        let sampled = HistoryAnalyzer.downsampleIndices(count: points.count, maxPoints: 600)
        let dates = sampled.map { points[$0].date }
        let chartSeries = metrics.enumerated().map { index, metric in
            SeriesChart.Series(
                dates: dates,
                values: sampled.map { points[$0][keyPath: metric.keyPath] },
                opacity: index == 0 ? 0.9 : 0.6,
                fillsArea: index == 0
            )
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let primary = stats.first {
                    StatChip(label: L10n.Charts.average, value: metrics[0].formatter(primary.average))
                    StatChip(label: primary.isEstimated ? L10n.Charts.peakEstimated : L10n.Charts.peak, value: metrics[0].formatter(primary.peak))
                }
            }

            SeriesChart(
                series: chartSeries,
                tint: tint,
                percentDomain: percentDomain
            )
            .frame(height: DesignSystem.Chart.height)
            .overlay {
                if metrics.allSatisfy({ metric in
                    points.allSatisfy { $0[keyPath: metric.keyPath] == nil }
                }) {
                    CollectingPlaceholder(text: L10n.Charts.establishingBaseline)
                }
            }

            if metrics.count > 1 {
                HStack(spacing: 12) {
                    ForEach(metrics.indices, id: \.self) { index in
                        let metric = metrics[index]
                        HStack(spacing: 4) {
                            Circle().fill(index == 0 ? tint : tint.opacity(0.55)).frame(width: 7, height: 7)
                            Text(metric.name).font(.caption).foregroundStyle(.secondary)
                            Text(metric.formatter(stats[index].average))
                                .font(.system(.caption, design: .rounded).weight(.medium).monospacedDigit())
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CurrentMetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MiniSparkline: View {
    let values: [Double?]
    var tint: Color = .accentColor
    var percentDomain: Bool = true

    var body: some View {
        MemoryTrendShape(values: values.compactMap { $0 }, percentDomain: percentDomain)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(height: DesignSystem.Chart.sparkline)
    }
}
