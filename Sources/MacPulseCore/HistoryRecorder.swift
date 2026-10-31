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
    /// Sorted by minuteStart; immutable between restores.
    private var restored: [MinuteBucket] = []
    /// Sorted by minuteStart; completed and flushed minutes of this session.
    private(set) var sessionBuckets: [MinuteBucket] = []
    private(set) var recentSamples: [TimestampedSnapshot] = []
    private var aggregator = MetricsAggregator()
    private var previousDate: Date?
    /// Minutes whose merged content includes fragments the current detail
    /// stream cannot represent (restored history, or data flushed by a clock
    /// rollback). They always keep their bucket representation in charts.
    private var nonDetailMinutes: Set<Date> = []

    mutating func restore(_ buckets: [MinuteBucket], now: Date) {
        restored = HistoryAnalyzer.retainedBuckets(HistoryAnalyzer.mergedBuckets(buckets), now: now)
        nonDetailMinutes.formUnion(restored.map(\.minuteStart))
    }

    @discardableResult
    mutating func record(_ snapshot: MetricsSnapshot, at date: Date) -> Bool {
        if let previousDate, date < previousDate {
            if let flushed = aggregator.flush(at: previousDate) {
                insert(flushed)
                nonDetailMinutes.insert(flushed.minuteStart)
            }
            recentSamples.removeAll(keepingCapacity: true)
        }
        previousDate = date
        recentSamples.append(TimestampedSnapshot(date: date, snapshot: snapshot))
        if recentSamples.count > Self.recentSampleLimit {
            recentSamples.removeFirst(recentSamples.count - Self.recentSampleLimit)
        }
        guard let completed = aggregator.append(snapshot, at: date) else { return false }
        insert(completed)
        prune(around: date)
        return true
    }

    mutating func flush(at date: Date) {
        if let partial = aggregator.flush(at: date) {
            insert(partial)
        }
    }

    func buckets(at now: Date) -> [MinuteBucket] {
        let cutoff = now.addingTimeInterval(-HistoryAnalyzer.retentionSeconds)
        // Linear merge of two sorted arrays: no dictionary build, no sort.
        var merged: [MinuteBucket] = []
        merged.reserveCapacity(restored.count + sessionBuckets.count + 1)
        var i = 0
        var j = 0
        while i < restored.count, j < sessionBuckets.count {
            let restoredStart = restored[i].minuteStart
            let sessionStart = sessionBuckets[j].minuteStart
            if restoredStart == sessionStart {
                merged.append(HistoryAnalyzer.mergedBucket(restored[i], sessionBuckets[j]))
                i += 1
                j += 1
            } else if restoredStart < sessionStart {
                merged.append(restored[i])
                i += 1
            } else {
                merged.append(sessionBuckets[j])
                j += 1
            }
        }
        merged.append(contentsOf: restored[i...])
        merged.append(contentsOf: sessionBuckets[j...])
        if let partial = aggregator.currentBucket {
            let index = insertionIndex(of: partial.minuteStart, in: merged)
            if index < merged.count, merged[index].minuteStart == partial.minuteStart {
                merged[index] = HistoryAnalyzer.mergedBucket(merged[index], partial)
            } else {
                merged.insert(partial, at: index)
            }
        }
        return merged.filter { $0.minuteStart > cutoff }
    }

    func series(for range: HistoryRange, now: Date) -> MetricSeries {
        let minutePoints = HistoryAnalyzer.minuteSeries(fromSorted: buckets(at: now), within: range.seconds, now: now)
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

    // Sorted-array maintenance: completing a minute is a binary-searched
    // upsert instead of re-merging and re-sorting the whole history.

    private mutating func insert(_ bucket: MinuteBucket) {
        let index = insertionIndex(of: bucket.minuteStart, in: sessionBuckets)
        if index < sessionBuckets.count, sessionBuckets[index].minuteStart == bucket.minuteStart {
            sessionBuckets[index] = HistoryAnalyzer.mergedBucket(sessionBuckets[index], bucket)
        } else {
            sessionBuckets.insert(bucket, at: index)
        }
    }

    private func insertionIndex(of date: Date, in buckets: [MinuteBucket]) -> Int {
        var low = 0
        var high = buckets.count
        while low < high {
            let mid = (low + high) / 2
            if buckets[mid].minuteStart < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private mutating func prune(around date: Date) {
        let cutoff = date.addingTimeInterval(-HistoryAnalyzer.retentionSeconds)
        prune(&restored, cutoff: cutoff)
        prune(&sessionBuckets, cutoff: cutoff)
        nonDetailMinutes = nonDetailMinutes.filter { $0 > cutoff }
    }

    private func prune(_ buckets: inout [MinuteBucket], cutoff: Date) {
        var low = 0
        var high = buckets.count
        while low < high {
            let mid = (low + high) / 2
            if buckets[mid].minuteStart <= cutoff { low = mid + 1 } else { high = mid }
        }
        if low > 0 { buckets.removeFirst(low) }
    }

    private static func minuteStart(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}
