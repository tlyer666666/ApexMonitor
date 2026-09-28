import SwiftUI

struct MetricRow: View {
    let title: String
    let symbol: String
    let value: String
    var detail: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

struct MemoryTrendShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let normalized = MemoryTrendGeometry.normalizedPoints(for: values)
        guard !normalized.isEmpty else { return Path() }
        let points = normalized.map { point in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(point.x),
                y: rect.minY + rect.height * CGFloat(point.y)
            )
        }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
