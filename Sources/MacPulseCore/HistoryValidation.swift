import Foundation

extension MinuteBucket {
    var isValidHistory: Bool {
        guard minuteStart.timeIntervalSince1970.isFinite,
              sampleCount > 0, sampleCount <= 1_000_000 else { return false }
        let percentages = [cpuAverage, cpuPeak, memoryAverage, memoryPeak]
        guard percentages.allSatisfy({ $0.map { $0.isFinite && (0...100).contains($0) } ?? true }) else { return false }
        let rates = [diskReadAverage, diskReadPeak, diskWriteAverage, diskWritePeak,
                     networkReceiveAverage, networkReceivePeak, networkSendAverage, networkSendPeak]
        guard rates.allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } ?? true }) else { return false }
        guard let metadata else { return true }
        let metrics = [metadata.cpu, metadata.memory, metadata.diskRead, metadata.diskWrite,
                       metadata.networkReceive, metadata.networkSend]
        guard metrics.allSatisfy({ value in
            value.validCount >= 0 && value.validCount <= sampleCount &&
            value.valueSum.isFinite && value.valueSum >= 0 &&
            value.validDurationSeconds.isFinite && value.validDurationSeconds >= 0 &&
            (value.totalBytes.map { $0.isFinite && $0 >= 0 } ?? true) &&
            (value.samplePeak.map { $0.isFinite && $0 >= 0 } ?? true)
        }), metadata.trafficCoverageSeconds.isFinite, metadata.trafficCoverageSeconds >= 0 else { return false }
        if let start = metadata.startTimestamp, let end = metadata.endTimestamp {
            return start.isFinite && end.isFinite && start <= end
        }
        return metadata.startTimestamp == nil && metadata.endTimestamp == nil
    }
}
