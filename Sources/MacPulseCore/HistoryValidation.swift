import Foundation

extension MinuteBucket {
    private static let tolerance = 1e-6

    var isValidHistory: Bool {
        guard minuteStart.timeIntervalSince1970.isFinite,
              sampleCount > 0, sampleCount <= 1_000_000 else { return false }

        // CPU and memory are percentages; rates are merely non-negative.
        let averages: [(value: Double?, isPercent: Bool)] = [
            (cpuAverage, true), (memoryAverage, true),
            (diskReadAverage, false), (diskWriteAverage, false),
            (networkReceiveAverage, false), (networkSendAverage, false)
        ]
        let peaks: [(value: Double?, isPercent: Bool)] = [
            (cpuPeak, true), (memoryPeak, true),
            (diskReadPeak, false), (diskWritePeak, false),
            (networkReceivePeak, false), (networkSendPeak, false)
        ]
        for entry in averages + peaks {
            guard let value = entry.value else { continue }
            guard value.isFinite, value >= 0, !entry.isPercent || value <= 100 else { return false }
        }

        guard let metadata else { return true }
        let metrics: [(value: MetricAggregateMetadata, isPercent: Bool)] = [
            (metadata.cpu, true), (metadata.memory, true),
            (metadata.diskRead, false), (metadata.diskWrite, false),
            (metadata.networkReceive, false), (metadata.networkSend, false)
        ]
        for metric in metrics {
            let value = metric.value
            guard value.validCount >= 0 && value.validCount <= sampleCount &&
                value.valueSum.isFinite && value.valueSum >= 0 &&
                value.validDurationSeconds.isFinite && value.validDurationSeconds >= 0 &&
                (value.totalBytes.map { $0.isFinite && $0 >= 0 } ?? true) &&
                (value.samplePeak.map { $0.isFinite && $0 >= 0 && (!metric.isPercent || $0 <= 100 + Self.tolerance) } ?? true)
            else { return false }
            if metric.isPercent, value.valueSum > Double(value.validCount) * 100 + Self.tolerance { return false }
            if value.validCount > 0, let peak = value.samplePeak,
               value.valueSum > Double(value.validCount) * peak * (1 + 1e-9) + 1e-9 { return false }
        }

        // Top-level display fields are derived from the metadata; both must
        // agree so chart lines and statistics cannot contradict each other.
        for (entry, metric) in zip(averages, metrics) {
            guard let average = entry.value else { continue }
            guard metric.value.validCount > 0 else { return false }
            let expected = metric.value.valueSum / Double(metric.value.validCount)
            guard abs(average - expected) <= Self.tolerance * max(1, abs(expected)) else { return false }
        }

        guard metadata.trafficCoverageSeconds.isFinite, metadata.trafficCoverageSeconds >= 0 else { return false }
        if let start = metadata.startTimestamp, let end = metadata.endTimestamp {
            return start.isFinite && end.isFinite && start <= end &&
                end <= minuteStart.timeIntervalSince1970 + 60 + Self.tolerance
        }
        return metadata.startTimestamp == nil && metadata.endTimestamp == nil
    }
}
