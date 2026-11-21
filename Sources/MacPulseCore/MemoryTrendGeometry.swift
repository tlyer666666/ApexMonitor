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
    /// Percent values map into a 0...100 domain. Rate values (bytes/second)
    /// must pass `percentDomain: false`; the percentage ceiling would clip
    /// ordinary traffic into a flat line.
    public static func normalizedPoints(for values: [Double], percentDomain: Bool = true) -> [NormalizedPoint] {
        normalizedSegments(for: values.map { Optional($0) }, percentDomain: percentDomain).flatMap { $0 }
    }

    /// Normalized points split into contiguous runs: a missing (`nil`) or
    /// non-finite sample breaks the line instead of being bridged over.
    public static func normalizedSegments(for values: [Double?], percentDomain: Bool = true) -> [[NormalizedPoint]] {
        guard !values.isEmpty else { return [] }
        let cleaned = values.map { value -> Double? in
            guard let value, value.isFinite, value >= 0 else { return nil }
            return percentDomain ? min(value, 100) : value
        }
        let present = cleaned.compactMap { $0 }
        guard !present.isEmpty else { return [] }

        let lower: Double
        let range: Double
        if percentDomain {
            let minimum = present.min() ?? 0
            let maximum = present.max() ?? minimum
            let span = max(maximum - minimum, 1)
            lower = max(0, minimum - span * 0.2)
            let upper = min(100, maximum + span * 0.2)
            range = max(upper - lower, 1)
        } else {
            lower = 0
            range = max(present.max() ?? 0, 1)
        }

        var segments: [[NormalizedPoint]] = []
        var run: [NormalizedPoint] = []
        for (index, value) in cleaned.enumerated() {
            if let value {
                run.append(NormalizedPoint(
                    x: cleaned.count == 1 ? 0.5 : Double(index) / Double(cleaned.count - 1),
                    y: 1 - (value - lower) / range
                ))
            } else if !run.isEmpty {
                segments.append(run)
                run = []
            }
        }
        if !run.isEmpty { segments.append(run) }
        return segments
    }
}
