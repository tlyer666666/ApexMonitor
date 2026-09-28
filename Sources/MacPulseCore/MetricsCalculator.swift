import Foundation

public struct MetricsCalculator {
    private var previous: RawMetricsSample?

    public init() {}

    public mutating func update(_ sample: RawMetricsSample) -> MetricsSnapshot {
        let elapsed: Double? = {
            guard let previous else { return nil }
            let value = sample.uptime - previous.uptime
            guard value.isFinite, value > 0 else { return nil }
            return value
        }()

        let cpuPercent: Double? = {
            guard elapsed != nil,
                  let previous,
                  let oldCPU = previous.cpu,
                  let newCPU = sample.cpu else { return nil }
            guard let user = nonnegativeDelta(oldCPU.user, newCPU.user),
                  let system = nonnegativeDelta(oldCPU.system, newCPU.system),
                  let idle = nonnegativeDelta(oldCPU.idle, newCPU.idle),
                  let nice = nonnegativeDelta(oldCPU.nice, newCPU.nice) else { return nil }
            let total = user + system + idle + nice
            guard total > 0 else { return nil }
            let value = Double(user + system + nice) / Double(total) * 100
            guard value.isFinite else { return nil }
            return min(max(value, 0), 100)
        }()

        let memoryPercent: Double? = {
            guard let used = sample.memoryUsedBytes,
                  let total = sample.memoryTotalBytes,
                  total > 0 else { return nil }
            return min(max(Double(used) / Double(total) * 100, 0), 100)
        }()

        let snapshot = MetricsSnapshot(
            timestamp: sample.uptime,
            cpuPercent: cpuPercent,
            memoryUsedBytes: sample.memoryUsedBytes,
            memoryTotalBytes: sample.memoryTotalBytes,
            memoryPercent: memoryPercent,
            diskReadBytesPerSecond: rate(from: previous?.diskReadBytes, to: sample.diskReadBytes, elapsed: elapsed),
            diskWriteBytesPerSecond: rate(from: previous?.diskWrittenBytes, to: sample.diskWrittenBytes, elapsed: elapsed),
            networkReceiveBytesPerSecond: networkRate(from: previous?.networkReceivedBytes, to: sample.networkReceivedBytes, elapsed: elapsed),
            networkSendBytesPerSecond: networkRate(from: previous?.networkSentBytes, to: sample.networkSentBytes, elapsed: elapsed)
        )
        previous = sample
        return snapshot
    }

    private func networkRate(from old: UInt64?, to new: UInt64?, elapsed: Double?) -> Double? {
        guard let old, let new else { return nil }
        let delta: UInt64
        if new >= old {
            delta = new - old
        } else if old <= UInt64(UInt32.max),
                  new <= UInt64(UInt32.max) / 10,
                  old >= UInt64(UInt32.max) * 9 / 10 {
            delta = UInt64(UInt32.max) - old + new + 1
        } else {
            return nil
        }
        guard let elapsed else { return nil }
        let result = Double(delta) / elapsed
        guard result.isFinite, result >= 0 else { return nil }
        return result
    }

    private func rate(from old: UInt64?, to new: UInt64?, elapsed: Double?) -> Double? {
        guard let old, let new, let elapsed,
              let delta = nonnegativeDelta(old, new) else { return nil }
        let result = Double(delta) / elapsed
        guard result.isFinite, result >= 0 else { return nil }
        return result
    }

    private func nonnegativeDelta(_ old: UInt64, _ new: UInt64) -> UInt64? {
        guard new >= old else { return nil }
        return new - old
    }
}
