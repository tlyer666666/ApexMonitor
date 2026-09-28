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
    @Published private(set) var processSummary: ProcessSummary?
    @Published private(set) var volumes: [VolumeSpace] = []
    @Published private(set) var interfaces: [InterfaceDetail] = []
    @Published private(set) var interfaceRuntimeTotals: [String: NetworkInterfaceCounters] = [:]
    @Published private(set) var pathStatus: NetworkPathStatus?
    @Published private(set) var loadAverage: LoadAverage?
    /// Navigation and range state live here (not in SwiftUI @State) so the
    /// dashboard window can stop detail sampling on close and still restore
    /// the selected range when reopened.
    @Published var navigationPath: [MetricCategory] = []
    @Published var selectedRange: HistoryRange = .fifteenMinutes

    private let sampler = MetricsSampler()
    private let historyFile: HistoryFileStore
    private var aggregator = MetricsAggregator()
    private let historyQueue = DispatchQueue(label: "com.macpulse.history", qos: .utility)
    private let detailQueue = DispatchQueue(label: "com.macpulse.detail", qos: .utility)
    private let detailEngine = DetailEngine()
    private var detailTimer: DispatchSourceTimer?
    private var pathMonitor: NetworkPathMonitor?
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
        sampler.start(
            deliver: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.accept(snapshot)
                }
            },
            onInterfaceTotals: { [weak self] totals in
                Task { @MainActor [weak self] in
                    self?.interfaceRuntimeTotals = totals
                }
            }
        )
        pathMonitor = NetworkPathMonitor { [weak self] status in
            Task { @MainActor [weak self] in
                self?.pathStatus = status
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
        stopDetailTimer()
        pathMonitor?.cancel()
        pathMonitor = nil
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

    // MARK: - Live detail sampling

    /// Category-dependent detail sampling. Runs only while a detail page is
    /// open, at ~0.5 Hz, on a utility queue; process/volume/interface reads
    /// never touch the main thread. The process table is re-baselined on each
    /// begin so the first tick reflects the current moment, not the closed gap.
    func beginLiveDetail(_ category: MetricCategory) {
        detailQueue.async { [detailEngine] in
            detailEngine.activeCategory = category
            detailEngine.processTable = ProcessTable()
        }
        startDetailTimerIfNeeded()
    }

    func endLiveDetail() {
        detailQueue.async { [detailEngine] in
            detailEngine.activeCategory = nil
        }
        stopDetailTimer()
    }

    private func startDetailTimerIfNeeded() {
        guard detailTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: detailQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self, detailEngine] in
            guard let self else { return }
            guard let category = detailEngine.activeCategory else { return }
            let now = Date().timeIntervalSince1970
            var summary: ProcessSummary?
            var load: LoadAverage?
            var volumes: [VolumeSpace] = []
            var interfaces: [InterfaceDetail] = []

            switch category {
            case .cpu, .memory:
                summary = detailEngine.processTable.update(detailEngine.processSampler.read(), at: now)
                load = SystemDetailReader.loadAverage()
            case .disk:
                volumes = VolumeSpaceReader.read()
            case .network:
                interfaces = detailEngine.systemReader.readInterfaceDetails()
            }

            Task { @MainActor [weak self] in
                self?.processSummary = summary
                self?.loadAverage = load
                self?.volumes = volumes
                self?.interfaces = interfaces
            }
        }
        detailTimer = timer
        timer.resume()
    }

    private func stopDetailTimer() {
        detailTimer?.setEventHandler {}
        detailTimer?.cancel()
        detailTimer = nil
    }
}

/// State confined to the detail queue; touches the process table and the
/// reader only from that serial queue.
private final class DetailEngine: @unchecked Sendable {
    var activeCategory: MetricCategory?
    let processSampler = ProcessSampler()
    let systemReader = SystemMetricsReader()
    var processTable = ProcessTable()
}
