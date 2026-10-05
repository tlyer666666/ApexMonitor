import Foundation

public struct NormalizedPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum MemoryTrendGeometry {
    public static func normalizedPoints(for values: [Double]) -> [NormalizedPoint] {
        guard !values.isEmpty else { return [] }
        let safeValues = values.map { min(max($0.isFinite ? $0 : 0, 0), 100) }
        let minimum = safeValues.min() ?? 0
        let maximum = safeValues.max() ?? minimum
        let span = max(maximum - minimum, 1)
        let lower = max(0, minimum - span * 0.2)
        let upper = min(100, maximum + span * 0.2)
        let range = max(upper - lower, 1)

        return safeValues.enumerated().map { index, value in
            NormalizedPoint(
                x: safeValues.count == 1 ? 0.5 : Double(index) / Double(safeValues.count - 1),
                y: 1 - (value - lower) / range
            )
        }
    }
}
