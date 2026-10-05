import Foundation

private func sample(_ cpu: Double, _ receive: Double, duration: Double = 1) -> MetricsSnapshot {
    .init(timestamp: 0, cpuPercent: cpu, memoryUsedBytes: 1, memoryTotalBytes: 2,
          memoryPercent: 50, diskReadBytesPerSecond: nil, diskWriteBytesPerSecond: nil,
          networkReceiveBytesPerSecond: receive, networkSendBytesPerSecond: 0,
          sampleDurationSeconds: duration)
}

@main
struct RecorderTests {
    static func main() {
        let base = Date(timeIntervalSince1970: 1_700_006_400)
        var aggregator = MetricsAggregator()
        _ = aggregator.append(sample(20, 100), at: base.addingTimeInterval(10))
        let restored = aggregator.flush(at: base.addingTimeInterval(11))!
        var recorder = HistoryRecorder()
        recorder.restore([restored], now: base.addingTimeInterval(20))
        recorder.record(sample(40, 200), at: base.addingTimeInterval(20))
        recorder.record(sample(60, 300), at: base.addingTimeInterval(65))
        let buckets = recorder.buckets(at: base.addingTimeInterval(66))
        guard buckets.count == 2, buckets.first?.sampleCount == 2 else { exit(1) }
        print("PASS: live restart fragments are canonical before saving")
        let series = recorder.series(for: .fiveMinutes, now: base.addingTimeInterval(66))
        let traffic = HistoryAnalyzer.trafficStatistics(series.trafficPoints, sampleSpacing: series.spacing)
        guard traffic.receivedBytes == 600, traffic.coverageSeconds == 3 else { exit(1) }
        print("PASS: restored fragments and current partial minute conserve traffic")
        guard !series.points.isEmpty else { exit(1) }
        print("PASS: current session appears immediately without a half-window grace period")
        recorder.record(sample(90, 900), at: base.addingTimeInterval(120))
        let rolledBack = recorder.series(for: .fiveMinutes, now: base.addingTimeInterval(66))
        guard rolledBack.points.allSatisfy({ $0.date <= base.addingTimeInterval(66) }) else { exit(1) }
        print("PASS: backward wall clocks cannot include future samples")
        recorder.flush(at: base.addingTimeInterval(121))
        let before = recorder.sessionBuckets.count
        recorder.flush(at: base.addingTimeInterval(122))
        guard recorder.sessionBuckets.count == before else { exit(1) }
        print("PASS: repeated recorder flush is idempotent")

        var rollback = HistoryRecorder()
        rollback.record(sample(1, 111), at: base.addingTimeInterval(180))
        rollback.record(sample(1, 222), at: base.addingTimeInterval(30))
        rollback.record(sample(1, 333), at: base.addingTimeInterval(90))
        let catchup = rollback.series(for: .fiveMinutes, now: base.addingTimeInterval(190))
        let recovered = HistoryAnalyzer.trafficStatistics(catchup.trafficPoints, sampleSpacing: 60)
        guard recovered.receivedBytes == 666 else {
            fputs("FAIL: rollback deleted recorded bytes that should reappear after catch-up\n", stderr)
            exit(1)
        }
        print("PASS: clock rollback hides future data without destroying it")

        var mixed = HistoryRecorder()
        for i in 0..<120 { mixed.record(sample(i < 60 ? 0 : 100, 1), at: base.addingTimeInterval(Double(i))) }
        let live = mixed.series(for: .fiveMinutes, now: base.addingTimeInterval(120))
        let liveMean = HistoryAnalyzer.statistics(live.points, metric: \.cpu).average
        var restart = HistoryRecorder()
        restart.restore(mixed.buckets(at: base.addingTimeInterval(120)), now: base.addingTimeInterval(120))
        let restoredMean = HistoryAnalyzer.statistics(restart.series(for: .fiveMinutes, now: base.addingTimeInterval(120)).points, metric: \.cpu).average
        guard liveMean == 50, restoredMean == 50 else {
            fputs("FAIL: mixed-resolution means disagree with the actual 120-sample mean\n", stderr)
            exit(1)
        }
        print("PASS: mixed-resolution and restored series have the same weighted mean")
    }
}
