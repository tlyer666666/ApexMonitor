import Foundation

@main
struct SamplingTests {
    static func raw() -> RawMetricsSample {
        .init(uptime: ProcessInfo.processInfo.systemUptime, cpu: nil, memoryUsedBytes: 1,
              memoryTotalBytes: 2, diskReadBytes: nil, diskWrittenBytes: nil,
              networkReceivedBytes: nil, networkSentBytes: nil)
    }

    @MainActor static func main() async {
        // Interface kind classification drives the link-state labels:
        // loopback/tunnels/bridges are infrastructure, never "connected".
        func detail(_ name: String) -> InterfaceDetail {
            InterfaceDetail(name: name, isUp: true, isRunning: true, ipv4: [], ipv6: [])
        }
        let loopback = detail("lo0")
        guard loopback.kind == .loopback && !loopback.isConnected else { exit(1) }
        print("PASS: loopback interface never reports a connected link")
        let tunnel = detail("utun3")
        guard tunnel.kind == .tunnel && !tunnel.isConnected else { exit(1) }
        let gif = detail("gif0")
        guard gif.kind == .tunnel else { exit(1) }
        print("PASS: tunnel interfaces are labeled virtual, not connected")
        let bridge = detail("bridge0")
        guard bridge.kind == .bridge && !bridge.isConnected else { exit(1) }
        print("PASS: bridge interfaces are labeled as bridges")
        let upLink = detail("en0")
        guard upLink.kind == .physical && upLink.isConnected else { exit(1) }
        let downLink = InterfaceDetail(name: "en1", isUp: false, isRunning: false, ipv4: [], ipv6: [])
        guard downLink.kind == .physical && !downLink.isConnected else { exit(1) }
        print("PASS: physical interfaces keep the connected/disconnected state")

        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let sampler = MetricsSampler(interval: 60, read: { _ in
            started.signal()
            _ = release.wait(timeout: .now() + 3)
            return raw()
        }, interfaces: { nil })
        var deliveries = 0
        sampler.start { _, _, _, _ in deliveries += 1 }
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
        temporary?.start { _, _, _, _ in }
        temporary = nil
        guard reference == nil else { exit(1) }
        print("PASS: releasing the main sampler cancels its timer")
    }
}
