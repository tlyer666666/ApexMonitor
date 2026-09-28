import SwiftUI

struct SeriesChart: View {
    let values: [Double?]
    let tint: Color
    let percentDomain: Bool

    var body: some View {
        Canvas { context, size in
            let resolved = resolvedValues()
            guard !resolved.isEmpty else { return }
            let maxValue = domainMax(from: resolved)

            for index in 0..<3 {
                let y = size.height * CGFloat(index) / 2
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.primary.opacity(0.07)), lineWidth: 1)
            }

            var run: [(x: CGFloat, y: CGFloat)] = []
            for (index, value) in resolved.enumerated() {
                if let value {
                    let x = resolved.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(resolved.count - 1)
                    let ratio = min(max(value / maxValue, 0), 1)
                    run.append((x, size.height * (1 - CGFloat(ratio))))
                } else if !run.isEmpty {
                    strokeRun(run, in: &context, size: size)
                    run = []
                }
            }
            if !run.isEmpty {
                strokeRun(run, in: &context, size: size)
            }
        }
    }

    private func strokeRun(_ run: [(x: CGFloat, y: CGFloat)], in context: inout GraphicsContext, size: CGSize) {
        guard let first = run.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in run.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.stroke(
            path,
            with: .color(tint.opacity(0.9)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        var area = path
        area.addLine(to: CGPoint(x: run.last!.x, y: size.height))
        area.addLine(to: CGPoint(x: first.x, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .color(tint.opacity(0.10)))
    }

    private func resolvedValues() -> [Double?] {
        let clean = values.map { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return max(value, 0)
        }
        return HistoryAnalyzer.downsample(clean, maxPoints: 600)
    }

    private func domainMax(from values: [Double?]) -> Double {
        if percentDomain { return 100 }
        let present = values.compactMap { $0 }
        let peak = present.max() ?? 1
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
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let primary = stats.first {
                    StatChip(label: "平均", value: metrics[0].formatter(primary.average))
                    StatChip(label: "峰值", value: metrics[0].formatter(primary.peak))
                }
            }

            SeriesChart(
                values: points.map { $0[keyPath: metrics[0].keyPath] },
                tint: tint,
                percentDomain: percentDomain
            )
            .frame(height: 110)

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
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MiniSparkline: View {
    let values: [Double?]

    var body: some View {
        MemoryTrendShape(values: values.compactMap { $0 })
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(height: 24)
    }
}
