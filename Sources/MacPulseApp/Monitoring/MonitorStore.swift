import Combine
import Foundation

struct TimestampedSnapshot: Sendable {
    let date: Date
    let snapshot: MetricsSnapshot
}

@MainActor
final class MonitorStore: ObservableObject {
    static let recentSampleLimit = 7_200
    /// Disk writes are debounced to every Nth minute bucket; the final state
    /// is always saved on stop(), so a crash loses at most N-1 minutes.
    private static let saveEveryBuckets = 5

    @Published private(set) var snapshot: MetricsSnapshot?
    @Published private(set) var recentSamples: [TimestampedSnapshot] = []
    @Published private(set) var minuteBuckets: [MinuteBucket] = []

    private let sampler = MetricsSampler()
    private let historyFile: HistoryFileStore
    private var aggregator = MetricsAggregator()
    private let historyQueue = DispatchQueue(label: "com.macpulse.history", qos: .utility)
    private var historyLoaded = false
    private var bucketsSinceSave = 0
    private var minutePathCache: (range: HistoryRange, bucketCount: Int, minute: Date, points: [MetricPoint])?

    init(historyFile: HistoryFileStore = .defaultStore()) {
        self.historyFile = historyFile
    }

    func start() {
        let file = historyFile
        historyQueue.async { [weak self] in
            let loaded = HistoryAnalyzer.prunedBuckets(
                HistoryAnalyzer.mergedBuckets(file.load()),
                now: Date()
            )
            Task { @MainActor [weak self] in
                self?.adoptLoadedHistory(loaded)
            }
        }
        sampler.start { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.accept(snapshot)
            }
        }
    }

    private func adoptLoadedHistory(_ loaded: [MinuteBucket]) {
        // Merge instead of assigning in case a minute bucket was recorded
        // while the load was still in flight.
        minuteBuckets = HistoryAnalyzer.prunedBuckets(
            HistoryAnalyzer.mergedBuckets(minuteBuckets + loaded),
            now: Date()
        )
        historyLoaded = true
    }

    func stop() {
        sampler.stop()
        if let partial = aggregator.flush(at: Date()) {
            minuteBuckets.append(partial)
        }
        let wasLoaded = historyLoaded
        let current = minuteBuckets
        let now = Date()
        historyQueue.sync { [file = historyFile] in
            let buckets: [MinuteBucket]
            if wasLoaded {
                buckets = current
            } else {
                // Fast quit: the async load may not have landed yet, so merge
                // from disk here instead of overwriting history with [].
                buckets = HistoryAnalyzer.mergedBuckets(current + file.load())
            }
            _ = file.save(HistoryAnalyzer.prunedBuckets(buckets, now: now))
        }
    }

    func points(for range: HistoryRange) -> [MetricPoint] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-range.seconds)

        if range.seconds <= 3_600 {
            // Grace period: require the per-second buffer to cover at least
            // half the range before preferring it over minute buckets.
            let samples = recentSamples.filter { $0.date > cutoff }
            if samples.count >= 2,
               let oldest = samples.first,
               now.timeIntervalSince(oldest.date) >= range.seconds * 0.5 {
                return samples.map { MetricPoint(date: $0.date, snapshot: $0.snapshot) }
            }
        }
        let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        if let cache = minutePathCache,
           cache.range == range,
           cache.bucketCount == minuteBuckets.count,
           cache.minute == minute {
            return cache.points
        }
        let points = HistoryAnalyzer.minuteSeries(from: minuteBuckets, within: range.seconds, now: now)
        minutePathCache = (range, minuteBuckets.count, minute, points)
        return points
    }

    private func accept(_ snapshot: MetricsSnapshot) {
        self.snapshot = snapshot
        recentSamples.append(TimestampedSnapshot(date: Date(), snapshot: snapshot))
        if recentSamples.count > Self.recentSampleLimit {
            recentSamples.removeFirst(recentSamples.count - Self.recentSampleLimit)
        }

        if let completed = aggregator.append(snapshot, at: Date()) {
            minuteBuckets.append(completed)
            minuteBuckets = HistoryAnalyzer.prunedBuckets(minuteBuckets, now: Date())
            bucketsSinceSave += 1
            if bucketsSinceSave >= Self.saveEveryBuckets {
                bucketsSinceSave = 0
                saveHistory()
            }
        }
    }

    private func saveHistory() {
        let buckets = minuteBuckets
        let file = historyFile
        historyQueue.async {
            file.save(buckets)
        }
    }
}
