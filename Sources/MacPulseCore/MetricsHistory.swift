import Foundation

/// Per-metric aggregates for one minute bucket. validCount weights chart means;
/// durations and byte integrals are tracked separately from it.
public struct MetricAggregateMetadata: Codable, Sendable, Equatable {
    public fileprivate(set) var validCount: Int = 0
    public fileprivate(set) var valueSum: Double = 0
    public fileprivate(set) var validDurationSeconds: Double = 0
    public fileprivate(set) var totalBytes: Double?
    public fileprivate(set) var samplePeak: Double?

    public init() {}

    fileprivate var average: Double? {
        validCount > 0 ? valueSum / Double(validCount) : nil
    }

    fileprivate mutating func append(_ value: Double?, duration: Double, isRate: Bool = false) {
        guard let value, value.isFinite else { return }
        if isRate && (value < 0 || duration <= 0 || !(value * duration).isFinite) { return }
        validCount += 1
        valueSum += value
        validDurationSeconds += duration
        samplePeak = maximum(samplePeak, value)
        if isRate { totalBytes = (totalBytes ?? 0) + value * duration }
    }

    fileprivate func merged(with other: Self) -> Self {
        var result = self
        result.validCount += other.validCount
        result.valueSum += other.valueSum
        result.validDurationSeconds += other.validDurationSeconds
        result.totalBytes = added(totalBytes, other.totalBytes)
        result.samplePeak = maximum(samplePeak, other.samplePeak)
        return result
    }

    fileprivate func scaled(by fraction: Double) -> Self {
        var result = self
        result.validDurationSeconds *= fraction
        result.totalBytes = totalBytes.map { $0 * fraction }
        return result
    }

    /// Legacy averages have no recoverable per-metric denominator. Retain the
    /// old count-weighted display approximation, but never infer traffic bytes.
    fileprivate static func legacy(average: Double?, peak: Double?, count: Int) -> Self {
        var result = Self()
        if let average, average.isFinite {
            result.validCount = max(0, count)
            result.valueSum = average * Double(result.validCount)
        }
        result.samplePeak = peak.flatMap { $0.isFinite ? $0 : nil }
        return result
    }
}

/// Optional on persisted buckets: absence means legacy, NOT sixty seconds of
/// traffic. Coverage is the union of receive/send-valid sample durations.
public struct HistoryMetadata: Codable, Sendable, Equatable {
    public fileprivate(set) var cpu = MetricAggregateMetadata()
    public fileprivate(set) var memory = MetricAggregateMetadata()
    public fileprivate(set) var diskRead = MetricAggregateMetadata()
    public fileprivate(set) var diskWrite = MetricAggregateMetadata()
    public fileprivate(set) var networkReceive = MetricAggregateMetadata()
    public fileprivate(set) var networkSend = MetricAggregateMetadata()
    public fileprivate(set) var trafficCoverageSeconds: Double = 0
    public fileprivate(set) var hasLegacyGaps = false
    public fileprivate(set) var isEstimated = false
    /// Unix seconds, encoded as numbers so ISO8601 persistence cannot round
    /// fractional sample boundaries down to whole seconds.
    public fileprivate(set) var startTimestamp: Double?
    public fileprivate(set) var endTimestamp: Double?

    public init() {}

    fileprivate init(snapshot: MetricsSnapshot, at date: Date) {
        self.init()
        let supplied = snapshot.sampleDurationSeconds ?? 1
        let duration = supplied.isFinite && supplied > 0 ? supplied : 0
        cpu.append(snapshot.cpuPercent, duration: duration)
        memory.append(snapshot.memoryPercent, duration: duration)
        diskRead.append(snapshot.diskReadBytesPerSecond, duration: duration, isRate: true)
        diskWrite.append(snapshot.diskWriteBytesPerSecond, duration: duration, isRate: true)
        networkReceive.append(snapshot.networkReceiveBytesPerSecond, duration: duration, isRate: true)
        networkSend.append(snapshot.networkSendBytesPerSecond, duration: duration, isRate: true)
        if networkReceive.validCount > 0 || networkSend.validCount > 0 {
            trafficCoverageSeconds = duration
        }
        // Rates describe the interval ending at the sample, not the following
        // interval. Bounds let complete windows remain exact after persistence.
        startTimestamp = date.timeIntervalSince1970 - duration
        endTimestamp = date.timeIntervalSince1970
    }

    fileprivate init(legacy bucket: MinuteBucket) {
        self.init()
        cpu = .legacy(average: bucket.cpuAverage, peak: bucket.cpuPeak, count: bucket.sampleCount)
        memory = .legacy(average: bucket.memoryAverage, peak: bucket.memoryPeak, count: bucket.sampleCount)
        diskRead = .legacy(average: bucket.diskReadAverage, peak: bucket.diskReadPeak, count: bucket.sampleCount)
        diskWrite = .legacy(average: bucket.diskWriteAverage, peak: bucket.diskWritePeak, count: bucket.sampleCount)
        networkReceive = .legacy(average: bucket.networkReceiveAverage, peak: bucket.networkReceivePeak, count: bucket.sampleCount)
        networkSend = .legacy(average: bucket.networkSendAverage, peak: bucket.networkSendPeak, count: bucket.sampleCount)
        hasLegacyGaps = true
        isEstimated = true
        startTimestamp = bucket.minuteStart.timeIntervalSince1970
        endTimestamp = bucket.minuteStart.timeIntervalSince1970 + 60
    }

    fileprivate func merged(with other: Self) -> Self {
        var result = self
        result.cpu = cpu.merged(with: other.cpu)
        result.memory = memory.merged(with: other.memory)
        result.diskRead = diskRead.merged(with: other.diskRead)
        result.diskWrite = diskWrite.merged(with: other.diskWrite)
        result.networkReceive = networkReceive.merged(with: other.networkReceive)
        result.networkSend = networkSend.merged(with: other.networkSend)
        result.trafficCoverageSeconds += other.trafficCoverageSeconds
        result.hasLegacyGaps = hasLegacyGaps || other.hasLegacyGaps
        result.isEstimated = isEstimated || other.isEstimated
        result.startTimestamp = minimum(startTimestamp, other.startTimestamp)
        result.endTimestamp = maximum(endTimestamp, other.endTimestamp)
        return result
    }

    /// Boundaries inside a persisted bucket can only prorate integrals; the
    /// result is marked estimated, including its peaks.
    fileprivate func scaled(by fraction: Double) -> Self {
        guard fraction < 1 else { return self }
        var result = self
        result.cpu = cpu.scaled(by: fraction)
        result.memory = memory.scaled(by: fraction)
        result.diskRead = diskRead.scaled(by: fraction)
        result.diskWrite = diskWrite.scaled(by: fraction)
        result.networkReceive = networkReceive.scaled(by: fraction)
        result.networkSend = networkSend.scaled(by: fraction)
        result.trafficCoverageSeconds *= fraction
        result.isEstimated = true
        return result
    }

    fileprivate func metric(for keyPath: KeyPath<MetricPoint, Double?>) -> MetricAggregateMetadata? {
        switch keyPath {
        case \MetricPoint.cpu: return cpu
        case \MetricPoint.memory: return memory
        case \MetricPoint.diskRead: return diskRead
        case \MetricPoint.diskWrite: return diskWrite
        case \MetricPoint.networkReceive: return networkReceive
        case \MetricPoint.networkSend: return networkSend
        default: return nil
        }
    }
}

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
    public let metadata: HistoryMetadata?

    public init(
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
        networkSendPeak: Double?,
        metadata: HistoryMetadata? = nil
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
        self.metadata = metadata
    }

    fileprivate var resolvedMetadata: HistoryMetadata { metadata ?? HistoryMetadata(legacy: self) }

    fileprivate init(minuteStart: Date, sampleCount: Int, metadata: HistoryMetadata) {
        self.init(
            minuteStart: minuteStart, sampleCount: sampleCount,
            cpuAverage: metadata.cpu.average, cpuPeak: metadata.cpu.samplePeak,
            memoryAverage: metadata.memory.average, memoryPeak: metadata.memory.samplePeak,
            diskReadAverage: metadata.diskRead.average, diskReadPeak: metadata.diskRead.samplePeak,
            diskWriteAverage: metadata.diskWrite.average, diskWritePeak: metadata.diskWrite.samplePeak,
            networkReceiveAverage: metadata.networkReceive.average, networkReceivePeak: metadata.networkReceive.samplePeak,
            networkSendAverage: metadata.networkSend.average, networkSendPeak: metadata.networkSend.samplePeak,
            metadata: metadata
        )
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
    public let metadata: HistoryMetadata?

    public init(
        date: Date,
        cpu: Double?,
        memory: Double?,
        diskRead: Double?,
        diskWrite: Double?,
        networkReceive: Double?,
        networkSend: Double?,
        metadata: HistoryMetadata? = nil
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.networkReceive = networkReceive
        self.networkSend = networkSend
        self.metadata = metadata
    }

    public init(date: Date, snapshot: MetricsSnapshot) {
        self.init(
            date: date,
            cpu: snapshot.cpuPercent,
            memory: snapshot.memoryPercent,
            diskRead: snapshot.diskReadBytesPerSecond,
            diskWrite: snapshot.diskWriteBytesPerSecond,
            networkReceive: snapshot.networkReceiveBytesPerSecond,
            networkSend: snapshot.networkSendBytesPerSecond,
            metadata: HistoryMetadata(snapshot: snapshot, at: date)
        )
    }
}

public struct MetricStats: Sendable, Equatable {
    public let average: Double?
    public let peak: Double?
    public let minimum: Double?
    public var isEstimated: Bool = false
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
        case .fiveMinutes: return L10n.tr("5分钟", "5 min")
        case .fifteenMinutes: return L10n.tr("15分钟", "15 min")
        case .thirtyMinutes: return L10n.tr("30分钟", "30 min")
        case .oneHour: return L10n.tr("1小时", "1 hr")
        case .oneDay: return L10n.tr("24小时", "24 h")
        case .oneWeek: return L10n.tr("7天", "7 d")
        }
    }
}

public struct TrafficStatistics: Sendable, Equatable {
    /// Known contributions only when hasLegacyGaps is true; an entirely legacy
    /// series returns nil totals and zero known coverage, never mean * 60.
    public let receivedBytes: Double?
    public let sentBytes: Double?
    public let receivePeakPerSecond: Double?
    public let sendPeakPerSecond: Double?
    public let coverageSeconds: Double
    public var isEstimated: Bool = false
    public var hasLegacyGaps: Bool = false
}

public enum HistoryAnalyzer {
    public static let retentionSeconds: TimeInterval = 7 * 86_400

    /// Combines non-overlapping fragments, not repeated copies of one fragment.
    public static func mergedBuckets(_ buckets: [MinuteBucket]) -> [MinuteBucket] {
        var merged: [Date: MinuteBucket] = [:]
        for bucket in buckets {
            guard let existing = merged[bucket.minuteStart] else {
                merged[bucket.minuteStart] = bucket
                continue
            }
            merged[bucket.minuteStart] = MinuteBucket(
                minuteStart: bucket.minuteStart,
                sampleCount: existing.sampleCount + bucket.sampleCount,
                metadata: existing.resolvedMetadata.merged(with: bucket.resolvedMetadata)
            )
        }
        return merged.values.sorted { $0.minuteStart < $1.minuteStart }
    }

    /// Retention for storage must not delete observations just because a wall
    /// clock adjustment temporarily places their timestamp in the future.
    public static func retainedBuckets(_ buckets: [MinuteBucket], now: Date) -> [MinuteBucket] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        return buckets.filter { $0.minuteStart > cutoff }
    }

    public static func prunedBuckets(
        _ buckets: [MinuteBucket],
        now: Date,
        retentionSeconds: TimeInterval = HistoryAnalyzer.retentionSeconds
    ) -> [MinuteBucket] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        return buckets.filter { $0.minuteStart > cutoff && $0.minuteStart <= now }
    }

    public static func minuteSeries(
        from buckets: [MinuteBucket],
        within seconds: TimeInterval,
        now: Date
    ) -> [MetricPoint] {
        guard seconds.isFinite, seconds > 0 else { return [] }
        let end = now.timeIntervalSince1970
        let cutoff = end - seconds
        return buckets.sorted { $0.minuteStart < $1.minuteStart }.compactMap { bucket in
            guard bucket.minuteStart <= now else { return nil }
            let metadata = bucket.resolvedMetadata
            let start = metadata.startTimestamp ?? bucket.minuteStart.timeIntervalSince1970
            let finish = metadata.endTimestamp ?? bucket.minuteStart.timeIntervalSince1970 + 60
            let fraction: Double
            if finish > start {
                let overlap = min(finish, end) - max(start, cutoff)
                guard overlap > 0 else { return nil }
                fraction = min(1, overlap / (finish - start))
            } else {
                guard finish > cutoff, finish <= end else { return nil }
                fraction = 1
            }
            return MetricPoint(
                date: bucket.minuteStart,
                cpu: bucket.cpuAverage,
                memory: bucket.memoryAverage,
                diskRead: bucket.diskReadAverage,
                diskWrite: bucket.diskWriteAverage,
                networkReceive: bucket.networkReceiveAverage,
                networkSend: bucket.networkSendAverage,
                metadata: metadata.scaled(by: fraction)
            )
        }
    }

    public static func statistics(
        _ points: [MetricPoint],
        metric keyPath: KeyPath<MetricPoint, Double?>
    ) -> MetricStats {
        let values = points.compactMap { $0[keyPath: keyPath] }.filter(\.isFinite)
        let peaks = points.compactMap { point in
            point.metadata?.metric(for: keyPath)?.samplePeak ?? point[keyPath: keyPath]
        }.filter(\.isFinite)
        var sum = 0.0
        var count = 0.0
        for point in points {
            if let metric = point.metadata?.metric(for: keyPath) {
                guard metric.validCount > 0, metric.valueSum.isFinite else { continue }
                sum += metric.valueSum
                count += Double(metric.validCount)
            } else if let value = point[keyPath: keyPath], value.isFinite {
                sum += value
                count += 1
            }
        }
        return MetricStats(
            average: count > 0 && sum.isFinite ? sum / count : nil,
            peak: peaks.max(),
            minimum: values.min(),
            isEstimated: points.contains { $0.metadata?.isEstimated == true }
        )
    }

    /// Metadata wins over sampleSpacing; the spacing fallback only applies to
    /// raw points built without it, and that integration is marked estimated.
    public static func trafficStatistics(
        _ points: [MetricPoint],
        sampleSpacing seconds: Double
    ) -> TrafficStatistics {
        var received: Double?
        var sent: Double?
        var receivePeak: Double?
        var sendPeak: Double?
        var coverage = 0.0
        var estimated = false
        var legacy = false
        for point in points {
            if let metadata = point.metadata {
                received = added(received, metadata.networkReceive.totalBytes)
                sent = added(sent, metadata.networkSend.totalBytes)
                receivePeak = maximum(receivePeak, metadata.networkReceive.samplePeak)
                sendPeak = maximum(sendPeak, metadata.networkSend.samplePeak)
                coverage += metadata.trafficCoverageSeconds
                estimated = estimated || metadata.isEstimated
                legacy = legacy || metadata.hasLegacyGaps
            } else if seconds.isFinite, seconds > 0 {
                var counted = false
                if let rate = point.networkReceive, rate.isFinite, rate >= 0, (rate * seconds).isFinite {
                    received = (received ?? 0) + rate * seconds
                    receivePeak = maximum(receivePeak, rate)
                    counted = true
                }
                if let rate = point.networkSend, rate.isFinite, rate >= 0, (rate * seconds).isFinite {
                    sent = (sent ?? 0) + rate * seconds
                    sendPeak = maximum(sendPeak, rate)
                    counted = true
                }
                if counted { coverage += seconds; estimated = true }
            }
        }
        return TrafficStatistics(
            receivedBytes: received, sentBytes: sent,
            receivePeakPerSecond: receivePeak, sendPeakPerSecond: sendPeak,
            coverageSeconds: coverage, isEstimated: estimated, hasLegacyGaps: legacy
        )
    }

    public static func downsample(_ values: [Double?], maxPoints: Int) -> [Double?] {
        guard maxPoints > 0, values.count > maxPoints else { return values }
        let step = Double(values.count) / Double(maxPoints)
        return (0..<maxPoints).map { index in
            // With a single slot prefer the newest; with >= 2 keep both ends.
            let source = index == maxPoints - 1
                ? values.count - 1
                : Int((Double(index) * step).rounded(.down))
            return values[source]
        }
    }
}

public struct MetricsAggregator {
    private var minuteStart: Date?
    private var sampleCount = 0
    private var metadata = HistoryMetadata()

    public init() {}

    /// A non-consuming snapshot of the pending minute, safe for live queries.
    public var currentBucket: MinuteBucket? {
        guard let minuteStart, sampleCount > 0 else { return nil }
        return makeBucket(for: minuteStart)
    }

    public mutating func append(_ snapshot: MetricsSnapshot, at date: Date) -> MinuteBucket? {
        let minute = Self.minuteStart(of: date)
        var completed: MinuteBucket?
        if let current = minuteStart, minute != current {
            completed = makeBucket(for: current)
            reset()
        }
        if minuteStart == nil { minuteStart = minute }
        sampleCount += 1
        metadata = metadata.merged(with: HistoryMetadata(snapshot: snapshot, at: date))
        return completed
    }

    public mutating func flush(at date: Date) -> MinuteBucket? {
        guard let current = minuteStart, sampleCount > 0 else { return nil }
        let bucket = makeBucket(for: current)
        reset()
        return bucket
    }

    private func makeBucket(for minute: Date) -> MinuteBucket {
        MinuteBucket(minuteStart: minute, sampleCount: sampleCount, metadata: metadata)
    }

    private mutating func reset() {
        minuteStart = nil
        sampleCount = 0
        metadata = HistoryMetadata()
    }

    private static func minuteStart(of date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (seconds / 60).rounded(.down) * 60)
    }
}

private func added(_ first: Double?, _ second: Double?) -> Double? {
    guard first != nil || second != nil else { return nil }
    return (first ?? 0) + (second ?? 0)
}

private func maximum(_ first: Double?, _ second: Double?) -> Double? {
    switch (first, second) {
    case let (lhs?, rhs?): return max(lhs, rhs)
    case let (value?, nil), let (nil, value?): return value
    case (nil, nil): return nil
    }
}

private func minimum(_ first: Double?, _ second: Double?) -> Double? {
    switch (first, second) {
    case let (lhs?, rhs?): return min(lhs, rhs)
    case let (value?, nil), let (nil, value?): return value
    case (nil, nil): return nil
    }
}
