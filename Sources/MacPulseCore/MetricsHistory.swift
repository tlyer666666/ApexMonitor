import Foundation

public struct MinuteBucket: Codable, Sendable, Equatable {
    public let minuteStart: Date
    public let sampleCount: Int
    public let cpuAverage: Double?
    public let cpuPeak: Double?
    public let memoryAverage: Double?
    public let memoryPeak: Double?
    public let diskReadAverage: Double?
    public let diskReadPeak: Double?
    public let diskWriteAverage: Double?
    public let diskWritePeak: Double?
    public let networkReceiveAverage: Double?
    public let networkReceivePeak: Double?
    public let networkSendAverage: Double?
    public let networkSendPeak: Double?

    init(
        minuteStart: Date,
        sampleCount: Int,
        cpuAverage: Double?,
        cpuPeak: Double?,
        memoryAverage: Double?,
        memoryPeak: Double?,
        diskReadAverage: Double?,
        diskReadPeak: Double?,
        diskWriteAverage: Double?,
        diskWritePeak: Double?,
        networkReceiveAverage: Double?,
        networkReceivePeak: Double?,
        networkSendAverage: Double?,
        networkSendPeak: Double?
    ) {
        self.minuteStart = minuteStart
        self.sampleCount = sampleCount
        self.cpuAverage = cpuAverage
        self.cpuPeak = cpuPeak
        self.memoryAverage = memoryAverage
        self.memoryPeak = memoryPeak
        self.diskReadAverage = diskReadAverage
        self.diskReadPeak = diskReadPeak
        self.diskWriteAverage = diskWriteAverage
        self.diskWritePeak = diskWritePeak
        self.networkReceiveAverage = networkReceiveAverage
        self.networkReceivePeak = networkReceivePeak
        self.networkSendAverage = networkSendAverage
        self.networkSendPeak = networkSendPeak
    }
}

public struct MetricPoint: Sendable, Equatable {
    public let date: Date
    public let cpu: Double?
    public let memory: Double?
    public let diskRead: Double?
    public let diskWrite: Double?
    public let networkReceive: Double?
    public let networkSend: Double?

    public init(
        date: Date,
        cpu: Double?,
        memory: Double?,
        diskRead: Double?,
        diskWrite: Double?,
        networkReceive: Double?,
        networkSend: Double?
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.networkReceive = networkReceive
        self.networkSend = networkSend
    }

    public init(date: Date, snapshot: MetricsSnapshot) {
        self.init(
            date: date,
            cpu: snapshot.cpuPercent,
            memory: snapshot.memoryPercent,
            diskRead: snapshot.diskReadBytesPerSecond,
            diskWrite: snapshot.diskWriteBytesPerSecond,
            networkReceive: snapshot.networkReceiveBytesPerSecond,
            networkSend: snapshot.networkSendBytesPerSecond
        )
    }
}

public struct MetricStats: Sendable, Equatable {
    public let average: Double?
    public let peak: Double?
    public let minimum: Double?
}

public enum HistoryRange: String, CaseIterable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay
    case oneWeek

    public var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1_800
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        case .oneWeek: return 604_800
        }
    }

    public var label: String {
        switch self {
        case .fiveMinutes: return "5分钟"
        case .fifteenMinutes: return "15分钟"
        case .thirtyMinutes: return "30分钟"
        case .oneHour: return "1小时"
        case .oneDay: return "24小时"
        case .oneWeek: return "7天"
        }
    }
}

public enum HistoryAnalyzer {
    public static let retentionSeconds: TimeInterval = 7 * 86_400

    public static func mergedBuckets(_ buckets: [MinuteBucket]) -> [MinuteBucket] {
        var merged: [Date: MinuteBucket] = [:]
        for bucket in buckets {
            guard let existing = merged[bucket.minuteStart] else {
                merged[bucket.minuteStart] = bucket
                continue
            }
            merged[bucket.minuteStart] = merge(existing, bucket)
        }
        return merged.values.sorted { $0.minuteStart < $1.minuteStart }
    }

    public static func prunedBuckets(
        _ buckets: [MinuteBucket],
        now: Date,
        retentionSeconds: TimeInterval = HistoryAnalyzer.retentionSeconds
    ) -> [MinuteBucket] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        return buckets.filter { $0.minuteStart > cutoff }
    }

    public static func minuteSeries(
        from buckets: [MinuteBucket],
        within seconds: TimeInterval,
        now: Date
    ) -> [MetricPoint] {
        let cutoff = now.addingTimeInterval(-seconds)
        return buckets
            .filter { $0.minuteStart > cutoff && $0.minuteStart <= now }
            .sorted { $0.minuteStart < $1.minuteStart }
            .map { bucket in
                MetricPoint(
                    date: bucket.minuteStart,
                    cpu: bucket.cpuAverage,
                    memory: bucket.memoryAverage,
                    diskRead: bucket.diskReadAverage,
                    diskWrite: bucket.diskWriteAverage,
                    networkReceive: bucket.networkReceiveAverage,
                    networkSend: bucket.networkSendAverage
                )
            }
    }

    public static func statistics(
        _ points: [MetricPoint],
        metric keyPath: KeyPath<MetricPoint, Double?>
    ) -> MetricStats {
        let values = points.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return MetricStats(average: nil, peak: nil, minimum: nil) }
        let total = values.reduce(0, +)
        return MetricStats(
            average: total / Double(values.count),
            peak: values.max(),
            minimum: values.min()
        )
    }

    public static func downsample(_ values: [Double?], maxPoints: Int) -> [Double?] {
        guard maxPoints > 0, values.count > maxPoints else { return values }
        let step = Double(values.count) / Double(maxPoints)
        return (0..<maxPoints).map { index in
            // Pin the newest sample to the right edge of the decimated window.
            let source = index == maxPoints - 1
                ? values.count - 1
                : Int((Double(index) * step).rounded(.down))
            return values[source]
        }
    }

    private static func merge(_ older: MinuteBucket, _ newer: MinuteBucket) -> MinuteBucket {
        MinuteBucket(
            minuteStart: older.minuteStart,
            sampleCount: older.sampleCount + newer.sampleCount,
            cpuAverage: weightedAverage(older.cpuAverage, older.sampleCount, newer.cpuAverage, newer.sampleCount),
            cpuPeak: peak(older.cpuPeak, newer.cpuPeak),
            memoryAverage: weightedAverage(older.memoryAverage, older.sampleCount, newer.memoryAverage, newer.sampleCount),
            memoryPeak: peak(older.memoryPeak, newer.memoryPeak),
            diskReadAverage: weightedAverage(older.diskReadAverage, older.sampleCount, newer.diskReadAverage, newer.sampleCount),
            diskReadPeak: peak(older.diskReadPeak, newer.diskReadPeak),
            diskWriteAverage: weightedAverage(older.diskWriteAverage, older.sampleCount, newer.diskWriteAverage, newer.sampleCount),
            diskWritePeak: peak(older.diskWritePeak, newer.diskWritePeak),
            networkReceiveAverage: weightedAverage(older.networkReceiveAverage, older.sampleCount, newer.networkReceiveAverage, newer.sampleCount),
            networkReceivePeak: peak(older.networkReceivePeak, newer.networkReceivePeak),
            networkSendAverage: weightedAverage(older.networkSendAverage, older.sampleCount, newer.networkSendAverage, newer.sampleCount),
            networkSendPeak: peak(older.networkSendPeak, newer.networkSendPeak)
        )
    }

    private static func weightedAverage(_ first: Double?, _ firstCount: Int, _ second: Double?, _ secondCount: Int) -> Double? {
        switch (first, second) {
        case let (lhs?, rhs?):
            let total = firstCount + secondCount
            guard total > 0 else { return nil }
            return (lhs * Double(firstCount) + rhs * Double(secondCount)) / Double(total)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }

    private static func peak(_ first: Double?, _ second: Double?) -> Double? {
        switch (first, second) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }
}

struct MetricAccumulator {
    private var sum = 0.0
    private var peakValue = -Double.infinity
    private var count = 0

    mutating func append(_ value: Double?) {
        guard let value, value.isFinite else { return }
        sum += value
        peakValue = max(peakValue, value)
        count += 1
    }

    var average: Double? {
        count > 0 ? sum / Double(count) : nil
    }

    var peak: Double? {
        count > 0 ? peakValue : nil
    }
}

public struct MetricsAggregator {
    private var minuteStart: Date?
    private var sampleCount = 0
    private var cpu = MetricAccumulator()
    private var memory = MetricAccumulator()
    private var diskRead = MetricAccumulator()
    private var diskWrite = MetricAccumulator()
    private var networkReceive = MetricAccumulator()
    private var networkSend = MetricAccumulator()

    public init() {}

    public mutating func append(_ snapshot: MetricsSnapshot, at date: Date) -> MinuteBucket? {
        let minute = Self.minuteStart(of: date)
        var completed: MinuteBucket?
        if let current = minuteStart, minute != current {
            completed = makeBucket(for: current)
            reset()
        }
        if minuteStart == nil {
            minuteStart = minute
        }
        sampleCount += 1
        cpu.append(snapshot.cpuPercent)
        memory.append(snapshot.memoryPercent)
        diskRead.append(snapshot.diskReadBytesPerSecond)
        diskWrite.append(snapshot.diskWriteBytesPerSecond)
        networkReceive.append(snapshot.networkReceiveBytesPerSecond)
        networkSend.append(snapshot.networkSendBytesPerSecond)
        return completed
    }

    public mutating func flush(at date: Date) -> MinuteBucket? {
        guard let current = minuteStart, sampleCount > 0 else { return nil }
        let bucket = makeBucket(for: current)
        reset()
        return bucket
    }

    private func makeBucket(for minute: Date) -> MinuteBucket {
        MinuteBucket(
            minuteStart: minute,
            sampleCount: sampleCount,
            cpuAverage: cpu.average,
            cpuPeak: cpu.peak,
            memoryAverage: memory.average,
            memoryPeak: memory.peak,
            diskReadAverage: diskRead.average,
            diskReadPeak: diskRead.peak,
            diskWriteAverage: diskWrite.average,
            diskWritePeak: diskWrite.peak,
            networkReceiveAverage: networkReceive.average,
            networkReceivePeak: networkReceive.peak,
            networkSendAverage: networkSend.average,
            networkSendPeak: networkSend.peak
        )
    }

    private mutating func reset() {
        minuteStart = nil
        sampleCount = 0
        cpu = MetricAccumulator()
        memory = MetricAccumulator()
        diskRead = MetricAccumulator()
        diskWrite = MetricAccumulator()
        networkReceive = MetricAccumulator()
        networkSend = MetricAccumulator()
    }

    private static func minuteStart(of date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        let aligned = (seconds / 60).rounded(.down) * 60
        return Date(timeIntervalSince1970: aligned)
    }
}
