import Foundation

struct HistoryRepositoryResult: Sendable {
    let buckets: [MinuteBucket]
    let error: String?
}

// The disk baseline is immutable during one app session. Every write replaces
// it with baseline + the current session snapshot; no save re-merges its own
// previous output. All I/O and baseline state stay on this serial queue.
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
        } catch {
            baseline = []
            loadError = "历史文件读取失败，原文件已保留；本次数据仅暂存在内存。"
        }
    }

    private func write(_ session: [MinuteBucket], now: Date) -> HistoryRepositoryResult {
        ensureLoaded()
        let buckets = HistoryAnalyzer.retainedBuckets(
            HistoryAnalyzer.mergedBuckets((baseline ?? []) + session), now: now)
        guard loadError == nil else {
            return HistoryRepositoryResult(buckets: buckets, error: loadError)
        }
        let error = file.save(buckets) ? nil : "历史保存失败；本次数据仍在内存，下次保存将重试。"
        return HistoryRepositoryResult(buckets: buckets, error: error)
    }
}
