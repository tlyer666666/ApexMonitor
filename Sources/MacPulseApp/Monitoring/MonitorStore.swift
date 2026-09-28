import Combine
import Foundation

struct TimestampedSnapshot: Sendable {
    let date: Date
    let snapshot: MetricsSnapshot
}

@MainActor
final class MonitorStore: ObservableObject {
    static let recentSampleLimit = 7_200

    @Published private(set) var snapshot: MetricsSnapshot?
    @Published private(set) var recentSamples: [TimestampedSnapshot] = []
    @Published private(set) var minuteBuckets: [MinuteBucket] = []

    private let sampler = MetricsSampler()
    private let historyFile: HistoryFileStore
    private var aggregator = MetricsAggregator()
    private let historyQueue = DispatchQueue(label: "com.macpulse.history", qos: .utility)

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
                self?.minuteBuckets = loaded
            }
        }
        sampler.start { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.accept(snapshot)
            }
        }
    }

    func stop() {
        sampler.stop()
        if let partial = aggregator.flush(at: Date()) {
            minuteBuckets.append(partial)
            minuteBuckets = HistoryAnalyzer.prunedBuckets(minuteBuckets, now: Date())
        }
        // Serializing the final save through historyQueue prevents a queued
        // boundary save from overwriting it with stale buckets afterwards.
        historyQueue.sync {
            _ = historyFile.save(minuteBuckets)
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
        return HistoryAnalyzer.minuteSeries(from: minuteBuckets, within: range.seconds, now: now)
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
            saveHistory()
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
