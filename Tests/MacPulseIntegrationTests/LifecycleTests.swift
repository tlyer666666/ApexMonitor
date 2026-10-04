import Foundation

private final class ReadGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)

    func read(_ category: MetricCategory) -> DetailReading {
        if category == .disk {
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
            finished.signal()
            return .volumes([VolumeSpace(id: "/test", name: "test", totalBytes: 100, availableBytes: 20)])
        }
        return .interfaces([])
    }
}

@main
struct LifecycleTests {
    @MainActor private static var failures = 0

    @MainActor static func check(_ condition: Bool, _ label: String) {
        if condition { print("PASS: \(label)") }
        else { failures += 1; fputs("FAIL: \(label)\n", stderr) }
    }

    static func wait(_ semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + 3) == .success)
            }
        }
    }

    @MainActor static func testSwitchDiscardsPreviousResult() async {
        let gate = ReadGate()
        let sampler = DetailSampler(interval: 60, read: { gate.read($0) })
        var delivered: [String] = []
        sampler.start(.disk) { _ in delivered.append("disk") }
        check(await wait(gate.entered), "first detail read started")
        sampler.start(.network) { _ in delivered.append("network") }
        gate.release.signal()
        for _ in 0..<100 where delivered.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        check(delivered == ["network"], "switching category discards the older in-flight result")
        sampler.stop()
    }

    @MainActor static func testStopDiscardsPendingResult() async {
        let gate = ReadGate()
        let sampler = DetailSampler(interval: 60, read: { gate.read($0) })
        var delivered = 0
        sampler.start(.disk) { _ in delivered += 1 }
        check(await wait(gate.entered), "blocking detail read started before close")
        sampler.stop()
        gate.release.signal()
        check(await wait(gate.finished), "background read finished after close")
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(delivered == 0, "closing a detail session rejects all pending results")
        sampler.stop()
    }

    @MainActor static func testSamplerDoesNotRetainItself() async {
        weak var weakSampler: DetailSampler?
        var sampler: DetailSampler? = DetailSampler(interval: 60, read: { _ in .interfaces([]) })
        weakSampler = sampler
        sampler?.start(.network) { _ in }
        sampler = nil
        check(weakSampler == nil, "releasing a detail sampler cancels without a retain cycle")
    }

    @MainActor static func testStoreRejectsResultAfterClose() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macpulse-lifecycle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitorStore(historyFile: HistoryFileStore(directory: directory))
        store.beginLiveDetail(.memory)
        store.endLiveDetail()
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(store.processSummary == nil, "store remains empty after immediately closing details")
    }

    @MainActor static func main() async {
        await testSwitchDiscardsPreviousResult()
        await testStopDiscardsPendingResult()
        await testSamplerDoesNotRetainItself()
        await testStoreRejectsResultAfterClose()
        exit(failures == 0 ? 0 : 1)
    }
}
