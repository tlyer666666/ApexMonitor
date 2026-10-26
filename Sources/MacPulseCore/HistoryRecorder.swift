import Foundation

struct TimestampedSnapshot: Sendable {
    let date: Date
    let snapshot: MetricsSnapshot
}

struct MetricSeries: Sendable {
    let points: [MetricPoint]
    let trafficPoints: [MetricPoint]
    let spacing: Double
}

struct HistoryRecorder {
    static let recentSampleLimit = 7_200
    private var restored: [MinuteBucket] = []
    private(set) var sessionBuckets: [MinuteBucket] = []
    private(set) var recentSamples: [TimestampedSnapshot] = []
    private var aggregator = MetricsAggregator()
    private var previousDate: Date?
    /// Minutes whose merged content includes fragments the current detail
    /// stream cannot represent (restored history, or data flushed by a clock
    /// rollback). They always keep their bucket representation in charts.
    private var nonDetailMinutes: Set<Date> = []

    mutating func restore(_ buckets: [MinuteBucket], now: Date) {
        restored = canonical(buckets, now: now)
        nonDetailMinutes.formUnion(restored.map(\.minuteStart))
    }

    @discardableResult
    mutating func record(_ snapshot: MetricsSnapshot, at date: Date) -> Bool {
        if let previousDate, date < previousDate {
            flush(at: previousDate)
            if let flushed = sessionBuckets.last { nonDetailMinutes.insert(flushed.minuteStart) }
            recentSamples.removeAll(keepingCapacity: true)
        }
        previousDate = date
        recentSamples.append(TimestampedSnapshot(date: date, snapshot: snapshot))
        if recentSamples.count > Self.recentSampleLimit {
            recentSamples.removeFirst(recentSamples.count - Self.recentSampleLimit)
        }
        guard let completed = aggregator.append(snapshot, at: date) else { return false }
        sessionBuckets = canonical(sessionBuckets + [completed], now: date)
        restored = canonical(restored, now: date)
        nonDetailMinutes = nonDetailMinutes.filter {
            $0 > date.addingTimeInterval(-HistoryAnalyzer.retentionSeconds)
        }
        return true
    }

    mutating func flush(at date: Date) {
        if let partial = aggregator.flush(at: date) {
            sessionBuckets = canonical(sessionBuckets + [partial], now: date)
        }
    }

    func buckets(at now: Date) -> [MinuteBucket] {
        let partial = aggregator.currentBucket.map { [$0] } ?? []
        return canonical(restored + sessionBuckets + partial, now: now)
    }

    func series(for range: HistoryRange, now: Date) -> MetricSeries {
        let minutePoints = HistoryAnalyzer.minuteSeries(from: buckets(at: now), within: range.seconds, now: now)
        guard range.seconds <= 3_600, let first = recentSamples.first else {
            return MetricSeries(points: minutePoints, trafficPoints: minutePoints, spacing: 60)
        }
        let detailStart = Date(timeIntervalSince1970:
            (first.date.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)
        let cutoff = now.addingTimeInterval(-range.seconds)
        let detail = recentSamples.filter { $0.date >= detailStart && $0.date > cutoff && $0.date <= now }
            .map { MetricPoint(date: $0.date, snapshot: $0.snapshot) }
            .filter { !nonDetailMinutes.contains(Self.minuteStart(of: $0.date)) }
        // Replace a minute with per-second detail only when every fragment of
        // that minute lives in the current detail stream; otherwise keep the
        // canonical bucket so pre-rollback and restored data stay visible.
        let chart = minutePoints.filter { $0.date < detailStart || nonDetailMinutes.contains($0.date) } + detail
        return MetricSeries(points: chart, trafficPoints: minutePoints, spacing: 60)
    }

    private static func minuteStart(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private func canonical(_ buckets: [MinuteBucket], now: Date) -> [MinuteBucket] {
        HistoryAnalyzer.retainedBuckets(HistoryAnalyzer.mergedBuckets(buckets), now: now)
    }
}
