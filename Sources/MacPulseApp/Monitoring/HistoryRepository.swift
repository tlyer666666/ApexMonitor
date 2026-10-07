import Foundation

struct HistoryRepositoryResult: Sendable {
    let buckets: [MinuteBucket]
    let error: String?
}

// Each write is the fixed session-start baseline plus the current session
// snapshot, so a save never re-merges its own output. Serial queue only.
final class HistoryRepository: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macpulse.history", qos: .utility)
    private let file: HistoryFileStore
    private var baseline: [MinuteBucket]?
    private var loadError: String?

    init(file: HistoryFileStore) {
        self.file = file
    }

    func load(deliver: @escaping @Sendable (HistoryRepositoryResult) -> Void) {
        queue.async { [self] in
            ensureLoaded()
            deliver(HistoryRepositoryResult(buckets: baseline ?? [], error: loadError))
        }
    }

    func save(session: [MinuteBucket], now: Date, deliver: @escaping @Sendable (HistoryRepositoryResult) -> Void) {
        queue.async { [self] in deliver(write(session, now: now)) }
    }

    func saveAndWait(session: [MinuteBucket], now: Date) -> HistoryRepositoryResult {
        queue.sync { write(session, now: now) }
    }

    private func ensureLoaded() {
        guard baseline == nil else { return }
        do {
            baseline = HistoryAnalyzer.mergedBuckets(try file.read())
            loadError = nil
        } catch {
            baseline = []
            loadError = L10n.Errors.historyLoadFailed
        }
    }

    private func write(_ session: [MinuteBucket], now: Date) -> HistoryRepositoryResult {
        ensureLoaded()
        let buckets = HistoryAnalyzer.retainedBuckets(
            HistoryAnalyzer.mergedBuckets((baseline ?? []) + session), now: now)
        guard loadError == nil else {
            return HistoryRepositoryResult(buckets: buckets, error: loadError)
        }
        let error = file.save(buckets) ? nil : L10n.Errors.historySaveFailed
        return HistoryRepositoryResult(buckets: buckets, error: error)
    }
}
