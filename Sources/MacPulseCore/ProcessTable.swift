import Foundation

/// Process birth time from libproc; used only for identity, never for elapsed time.
public struct ProcessStartIdentity: Sendable, Equatable {
    public let seconds: UInt64
    public let microseconds: UInt64

    public init(seconds: UInt64, microseconds: UInt64) {
        self.seconds = seconds
        self.microseconds = microseconds
    }
}

public struct RawProcessSample: Sendable, Equatable {
    public let pid: Int32
    public let name: String?
    public let residentBytes: UInt64
    public let cpuTimeNanoseconds: UInt64
    public let startIdentity: ProcessStartIdentity?

    public init(
        pid: Int32,
        name: String?,
        residentBytes: UInt64,
        cpuTimeNanoseconds: UInt64,
        startIdentity: ProcessStartIdentity? = nil
    ) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.startIdentity = startIdentity
    }
}

public struct ProcessStat: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double?
    public let residentBytes: UInt64
}

public struct ProcessSummary: Sendable, Equatable {
    public let processCount: Int
    public let topByCPU: [ProcessStat]
    public let topByMemory: [ProcessStat]
}

/// Column the process list can be sorted by; value columns start high-to-low.
public enum ProcessSortColumn: String, CaseIterable, Sendable {
    case name
    case memory
    case cpu
}

public struct ProcessSortOrder: Sendable, Equatable {
    public let column: ProcessSortColumn
    public let ascending: Bool

    public init(column: ProcessSortColumn, ascending: Bool = false) {
        self.column = column
        self.ascending = ascending
    }

    /// The default cadence per column: values rank high-to-low, names A-to-Z.
    public init(column: ProcessSortColumn) {
        self.init(column: column, ascending: column == .name)
    }
}

extension ProcessSummary {
    /// The union of both ranked lists, deduplicated by PID and ordered for
    /// display. Unknown CPU values never masquerade as zero: they stay last
    /// in both directions. Ties fall back to ascending PID so the order is
    /// stable across refreshes.
    public func displayOrder(_ order: ProcessSortOrder) -> [ProcessStat] {
        var seen = Set<Int32>()
        var union: [ProcessStat] = []
        union.reserveCapacity(topByCPU.count + topByMemory.count)
        for stat in topByCPU + topByMemory where seen.insert(stat.pid).inserted {
            union.append(stat)
        }

        func isBefore(_ lhs: ProcessStat, _ rhs: ProcessStat) -> Bool {
            switch order.column {
            case .name:
                let left = lhs.name.lowercased()
                let right = rhs.name.lowercased()
                if left != right { return order.ascending ? left < right : left > right }
                return lhs.pid < rhs.pid
            case .memory:
                if lhs.residentBytes != rhs.residentBytes {
                    return order.ascending
                        ? lhs.residentBytes < rhs.residentBytes
                        : lhs.residentBytes > rhs.residentBytes
                }
                return lhs.pid < rhs.pid
            case .cpu:
                switch (lhs.cpuPercent, rhs.cpuPercent) {
                case (let left?, let right?):
                    if left != right { return order.ascending ? left < right : left > right }
                    return lhs.pid < rhs.pid
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.pid < rhs.pid
                }
            }
        }
        return union.sorted(by: isBefore)
    }
}

public struct ProcessTable {
    /// Top entries within the readable sample, not a census of all system processes.
    public static let topLimit = 10

    private struct State {
        var cpuTimeNanoseconds: UInt64
        var startIdentity: ProcessStartIdentity?
    }

    private var previous: [Int32: State] = [:]
    private var previousTime: Double?

    public init() {}

    /// `time` is monotonic system uptime in seconds, not a wall-clock timestamp.
    public mutating func update(_ samples: [RawProcessSample], at time: Double) -> ProcessSummary {
        let elapsed: Double? = {
            guard let previousTime else { return nil }
            let value = time - previousTime
            guard value.isFinite, value > 0 else { return nil }
            return value
        }()

        var stats: [ProcessStat] = []
        stats.reserveCapacity(samples.count)
        var next: [Int32: State] = [:]

        for sample in samples {
            let name = sample.name?.isEmpty == false ? sample.name! : "pid \(sample.pid)"
            let cpuPercent: Double?
            if let previous = previous[sample.pid],
               previous.startIdentity == sample.startIdentity,
               let elapsed,
               sample.cpuTimeNanoseconds >= previous.cpuTimeNanoseconds {
                let delta = sample.cpuTimeNanoseconds - previous.cpuTimeNanoseconds
                let percent = Double(delta) / (elapsed * 1_000_000_000) * 100
                cpuPercent = percent.isFinite ? max(percent, 0) : nil
            } else {
                // First sighting, changed identity, counter reset, or invalid
                // elapsed time: re-baseline instead of fabricating a rate.
                // Two nil identities retain legacy sample behavior.
                cpuPercent = nil
            }
            next[sample.pid] = State(
                cpuTimeNanoseconds: sample.cpuTimeNanoseconds,
                startIdentity: sample.startIdentity
            )
            stats.append(ProcessStat(pid: sample.pid, name: name, cpuPercent: cpuPercent, residentBytes: sample.residentBytes))
        }

        previous = next
        previousTime = time

        let topByCPU = ranked(stats) { $0.cpuPercent ?? -1 }.prefix(Self.topLimit)
        let topByMemory = ranked(stats) { Double($0.residentBytes) }.prefix(Self.topLimit)
        return ProcessSummary(
            processCount: samples.count,
            topByCPU: Array(topByCPU),
            topByMemory: Array(topByMemory)
        )
    }

    private func ranked(_ stats: [ProcessStat], by key: (ProcessStat) -> Double) -> [ProcessStat] {
        stats.sorted { key($0) > key($1) }
    }
}
