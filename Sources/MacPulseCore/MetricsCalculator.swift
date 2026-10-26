import Foundation

/// Sampling-validity policy shared by the scheduler and the calculator so the
/// configured cadence (1/2/5 seconds) and "this gap is an interruption" share
/// one bound: twice the cadence, never below the historical 5-second limit.
public enum SamplingValidity {
    public static func maxValidInterval(forConfiguredInterval configured: TimeInterval) -> TimeInterval {
        guard configured.isFinite, configured > 0 else { return 5 }
        return max(5, configured * 2)
    }

    public static func isSamplingGap(wallSeconds: TimeInterval, configuredInterval: TimeInterval) -> Bool {
        guard wallSeconds.isFinite, wallSeconds >= 0 else { return true }
        return wallSeconds > maxValidInterval(forConfiguredInterval: configuredInterval)
    }
}

public struct MetricsCalculator {
    private var previous: RawMetricsSample?
    public private(set) var maxValidInterval: Double

    public init(maxValidInterval: Double = 5) {
        guard maxValidInterval.isFinite, maxValidInterval > 0 else {
            preconditionFailure("maxValidInterval must be finite and positive")
        }
        self.maxValidInterval = maxValidInterval
    }

    public mutating func setMaxValidInterval(_ value: Double) {
        guard value.isFinite, value > 0 else { return }
        maxValidInterval = value
    }

    public mutating func update(_ sample: RawMetricsSample) -> MetricsSnapshot {
        let elapsed: Double? = {
            guard let previous else { return nil }
            let value = sample.uptime - previous.uptime
            guard value.isFinite, value > 0, value <= maxValidInterval else { return nil }
            return value
        }()

        let cpuBreakdown: (user: Double, system: Double, nice: Double, idle: Double)? = {
            guard elapsed != nil,
                  let previous,
                  let oldCPU = previous.cpu,
                  let newCPU = sample.cpu else { return nil }
            guard let user = nonnegativeDelta(oldCPU.user, newCPU.user),
                  let system = nonnegativeDelta(oldCPU.system, newCPU.system),
                  let idle = nonnegativeDelta(oldCPU.idle, newCPU.idle),
                  let nice = nonnegativeDelta(oldCPU.nice, newCPU.nice) else { return nil }
            let total = Double(user) + Double(system) + Double(idle) + Double(nice)
            guard total.isFinite, total > 0 else { return nil }
            let ratio: (UInt64) -> Double = { Double($0) / total * 100 }
            return (ratio(user), ratio(system), ratio(nice), ratio(idle))
        }()

        let cpuPercent: Double? = {
            guard let breakdown = cpuBreakdown else { return nil }
            let value = breakdown.user + breakdown.system + breakdown.nice
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
            cpuUserPercent: cpuBreakdown?.user,
            cpuSystemPercent: cpuBreakdown?.system,
            cpuNicePercent: cpuBreakdown?.nice,
            cpuIdlePercent: cpuBreakdown?.idle,
            memoryUsedBytes: sample.memoryUsedBytes,
            memoryTotalBytes: sample.memoryTotalBytes,
            memoryPercent: memoryPercent,
            diskReadBytesPerSecond: rate(from: previous?.diskReadBytes, to: sample.diskReadBytes, elapsed: elapsed),
            diskWriteBytesPerSecond: rate(from: previous?.diskWrittenBytes, to: sample.diskWrittenBytes, elapsed: elapsed),
            networkReceiveBytesPerSecond: rate(from: previous?.networkReceivedBytes, to: sample.networkReceivedBytes, elapsed: elapsed),
            networkSendBytesPerSecond: rate(from: previous?.networkSentBytes, to: sample.networkSentBytes, elapsed: elapsed),
            sampleDurationSeconds: elapsed ?? 0
        )
        previous = sample
        return snapshot
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
