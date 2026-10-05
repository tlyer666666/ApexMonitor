import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot: MetricsSnapshot?
    @Published private(set) var processSummary: ProcessSummary?
    @Published private(set) var volumes: [VolumeSpace] = []
    @Published private(set) var interfaces: [InterfaceDetail] = []
    @Published private(set) var interfaceRuntimeTotals: [String: NetworkInterfaceCounters] = [:]
    @Published private(set) var pathStatus: NetworkPathStatus?
    @Published private(set) var loadAverage: LoadAverage?
    @Published private(set) var historyError: String?
    @Published private(set) var lastUpdateDate: Date?
    @Published var navigationPath: [MetricCategory] = []
    @Published var selectedRange: HistoryRange = .fifteenMinutes
    /// Lives here (not in view @State) so the choice survives navigation.
    @Published var trafficRange: HistoryRange = .fifteenMinutes
    @Published private var historyRevision: UInt64 = 0

    private let sampler = MetricsSampler()
    private let repository: HistoryRepository
    private var history = HistoryRecorder()
    private let detailSampler = DetailSampler()
    private var detailCategory: MetricCategory?
    private var pathMonitor: NetworkPathMonitor?
    private var isRunning = false
    private var lifecycle: UInt64 = 0
    private var bucketsSinceSave = 0
    private var seriesCache: (range: HistoryRange, revision: UInt64, second: Int, value: MetricSeries)?

    init(historyFile: HistoryFileStore = .defaultStore()) {
        repository = HistoryRepository(file: historyFile)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lifecycle &+= 1
        let token = lifecycle
        repository.load { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.lifecycle == token else { return }
                self.history.restore(result.buckets, now: Date())
                self.historyError = result.error
                self.historyRevision &+= 1
            }
        }
        sampler.start { [weak self] snapshot, totals, date in
            guard let self, self.isRunning, self.lifecycle == token else { return }
            let completed = self.history.record(snapshot, at: date)
            self.interfaceRuntimeTotals = totals
            self.historyRevision &+= 1
            self.lastUpdateDate = date
            self.snapshot = snapshot
            if completed {
                self.bucketsSinceSave += 1
                if self.bucketsSinceSave >= 5 {
                    self.bucketsSinceSave = 0
                    self.saveHistory()
                }
            }
        }
        pathMonitor = NetworkPathMonitor { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.lifecycle == token else { return }
                self.pathStatus = status
            }
        }
    }

    func stop() {
        endLiveDetail()
        guard isRunning else { return }
        isRunning = false
        lifecycle &+= 1
        sampler.stop()
        pathMonitor?.cancel()
        pathMonitor = nil
        history.flush(at: Date())
        let result = repository.saveAndWait(session: history.sessionBuckets, now: Date())
        historyError = result.error
    }

    func points(for range: HistoryRange) -> [MetricPoint] {
        series(for: range).points
    }

    func series(for range: HistoryRange) -> MetricSeries {
        let now = Date()
        let second = Int(now.timeIntervalSince1970)
        if let cache = seriesCache, cache.range == range,
           cache.revision == historyRevision, cache.second == second {
            return cache.value
        }
        let result = history.series(for: range, now: now)
        seriesCache = (range, historyRevision, second, result)
        return result
    }

    private func saveHistory() {
        let token = lifecycle
        repository.save(session: history.sessionBuckets, now: Date()) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.lifecycle == token else { return }
                self.historyError = result.error
            }
        }
    }

    func beginLiveDetail(_ category: MetricCategory) {
        detailCategory = category
        clearDetails()
        detailSampler.start(category) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .processes(summary, load):
                self.processSummary = summary
                self.loadAverage = load
            case let .volumes(volumes):
                self.volumes = volumes
            case let .interfaces(interfaces):
                self.interfaces = interfaces
            }
        }
    }

    func endLiveDetail(_ category: MetricCategory? = nil) {
        if let category, category != detailCategory { return }
        detailSampler.stop()
        detailCategory = nil
        clearDetails()
    }

    private func clearDetails() {
        processSummary = nil
        loadAverage = nil
        volumes = []
        interfaces = []
    }
}
