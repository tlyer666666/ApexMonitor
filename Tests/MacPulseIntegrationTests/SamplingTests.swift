import Foundation

@main
struct SamplingTests {
    static func raw() -> RawMetricsSample {
        .init(uptime: ProcessInfo.processInfo.systemUptime, cpu: nil, memoryUsedBytes: 1,
              memoryTotalBytes: 2, diskReadBytes: nil, diskWrittenBytes: nil,
              networkReceivedBytes: nil, networkSentBytes: nil)
    }

    @MainActor static func main() async {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let sampler = MetricsSampler(interval: 60, read: { _ in
            started.signal()
            _ = release.wait(timeout: .now() + 3)
            return raw()
        }, interfaces: { nil })
        var deliveries = 0
        sampler.start { _, _, _ in deliveries += 1 }
        let entered = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: started.wait(timeout: .now() + 3) == .success)
            }
        }
        guard entered else { exit(1) }
        sampler.stop()
        release.signal()
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard deliveries == 0 else {
            fputs("FAIL: stopped main sampler published a queued snapshot\n", stderr)
            exit(1)
        }
        print("PASS: stopped main sampler rejects pending snapshots")

        weak var reference: MetricsSampler?
        var temporary: MetricsSampler? = MetricsSampler(interval: 60, read: { _ in raw() }, interfaces: { nil })
        reference = temporary
        temporary?.start { _, _, _ in }
        temporary = nil
        guard reference == nil else { exit(1) }
        print("PASS: releasing the main sampler cancels its timer")
    }
}
