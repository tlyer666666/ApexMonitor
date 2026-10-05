import Foundation

private let historyBase = Date(timeIntervalSince1970: 1_700_006_400)

private func makeSnapshot(cpu: Double?, memory: Double? = 50, diskRead: Double? = 100, diskWrite: Double? = 100, netRx: Double? = 1_000, netTx: Double? = 2_000) -> MetricsSnapshot {
    MetricsSnapshot(
        timestamp: 0,
        cpuPercent: cpu,
        memoryUsedBytes: memory == nil ? nil : 1,
        memoryTotalBytes: memory == nil ? nil : 2,
        memoryPercent: memory,
        diskReadBytesPerSecond: diskRead,
        diskWriteBytesPerSecond: diskWrite,
        networkReceiveBytesPerSecond: netRx,
        networkSendBytesPerSecond: netTx
    )
}

func testAggregatorEmitsBucketWhenMinuteRolls() {
    var aggregator = MetricsAggregator()
    let first = aggregator.append(makeSnapshot(cpu: 20, memory: 40), at: historyBase.addingTimeInterval(30))
    expect(first == nil, "samples inside one minute do not complete a bucket yet")

    let second = aggregator.append(makeSnapshot(cpu: 40, memory: 60), at: historyBase.addingTimeInterval(50))
    expect(second == nil, "second sample in the same minute still keeps accumulating")

    let completed = aggregator.append(makeSnapshot(cpu: 10, memory: 10), at: historyBase.addingTimeInterval(70))
    guard let bucket = completed else {
        expect(false, "crossing a minute boundary emits the previous minute bucket")
        return
    }
    expect(bucket.minuteStart == historyBase, "completed bucket is aligned to the minute start")
    expect(bucket.sampleCount == 2, "completed bucket counts the two samples it aggregated")
    expectNear(bucket.cpuAverage, 30, "cpu bucket average is computed from its samples")
    expectNear(bucket.cpuPeak, 40, "cpu bucket peak is the maximum sample")
    expectNear(bucket.memoryAverage, 50, "memory bucket average is computed from its samples")
    expectNear(bucket.memoryPeak, 60, "memory bucket peak is the maximum sample")
}

func testAggregatorFlushEmitsPartialBucketWithoutLosingData() {
    var aggregator = MetricsAggregator()
    _ = aggregator.append(makeSnapshot(cpu: 20, memory: 40), at: historyBase.addingTimeInterval(30))
    let partial = aggregator.flush(at: historyBase.addingTimeInterval(40))
    guard let bucket = partial else {
        expect(false, "flush emits the partial minute bucket")
        return
    }
    expect(bucket.sampleCount == 1, "partial bucket contains the samples seen so far")
    expectNear(bucket.cpuAverage, 20, "partial bucket keeps its own average")
    expect(aggregator.flush(at: historyBase.addingTimeInterval(41)) == nil, "flushing twice emits nothing more")
}

func testMergedBucketsCombinesDuplicateMinutes() {
    let first = MinuteBucket(
        minuteStart: historyBase, sampleCount: 2,
        cpuAverage: 30, cpuPeak: 40,
        memoryAverage: 50, memoryPeak: 60,
        diskReadAverage: 100, diskReadPeak: 100,
        diskWriteAverage: 100, diskWritePeak: 100,
        networkReceiveAverage: 1_000, networkReceivePeak: 1_000,
        networkSendAverage: 2_000, networkSendPeak: 2_000
    )
    let second = MinuteBucket(
        minuteStart: historyBase, sampleCount: 1,
        cpuAverage: 60, cpuPeak: 60,
        memoryAverage: 30, memoryPeak: 30,
        diskReadAverage: 300, diskReadPeak: 300,
        diskWriteAverage: 300, diskWritePeak: 300,
        networkReceiveAverage: 3_000, networkReceivePeak: 3_000,
        networkSendAverage: 4_000, networkSendPeak: 4_000
    )
    let merged = HistoryAnalyzer.mergedBuckets([first, second])
    expect(merged.count == 1, "duplicate minute buckets are merged into one")
    guard let bucket = merged.first else { return }
    expect(bucket.sampleCount == 3, "merged bucket keeps the combined sample count")
    expectNear(bucket.cpuAverage, 40, "merged cpu average is weighted by sample counts")
    expectNear(bucket.cpuPeak, 60, "merged cpu peak is the maximum of both buckets")
}

func testPruneRemovesBucketsOutsideRetention() {
    let now = historyBase.addingTimeInterval(8 * 86_400)
    let old = MinuteBucket(
        minuteStart: now.addingTimeInterval(-8 * 86_400), sampleCount: 1,
        cpuAverage: 1, cpuPeak: 1, memoryAverage: 1, memoryPeak: 1,
        diskReadAverage: 1, diskReadPeak: 1, diskWriteAverage: 1, diskWritePeak: 1,
        networkReceiveAverage: 1, networkReceivePeak: 1, networkSendAverage: 1, networkSendPeak: 1
    )
    let recent = MinuteBucket(
        minuteStart: now.addingTimeInterval(-86_400), sampleCount: 1,
        cpuAverage: 2, cpuPeak: 2, memoryAverage: 2, memoryPeak: 2,
        diskReadAverage: 2, diskReadPeak: 2, diskWriteAverage: 2, diskWritePeak: 2,
        networkReceiveAverage: 2, networkReceivePeak: 2, networkSendAverage: 2, networkSendPeak: 2
    )
    let kept = HistoryAnalyzer.prunedBuckets([old, recent], now: now)
    expect(kept.count == 1, "buckets older than the retention window are removed")
    expect(kept.first?.cpuAverage == 2, "kept buckets are the recent ones")
}

func testMinuteSeriesFiltersWithinRangeAndSortsAscending() {
    let now = historyBase.addingTimeInterval(1_000)
    var buckets: [MinuteBucket] = []
    for offset in [600, 480, 360, 240, 180, 120, 60] {
        let cpu = Double(600 - offset) / 10
        buckets.append(MinuteBucket(
            minuteStart: now.addingTimeInterval(TimeInterval(-offset)), sampleCount: 1,
            cpuAverage: cpu, cpuPeak: cpu, memoryAverage: 50, memoryPeak: 50,
            diskReadAverage: 100, diskReadPeak: 100, diskWriteAverage: 100, diskWritePeak: 100,
            networkReceiveAverage: 1_000, networkReceivePeak: 1_000, networkSendAverage: 2_000, networkSendPeak: 2_000
        ))
    }
    let series = HistoryAnalyzer.minuteSeries(from: buckets, within: 300, now: now)
    expect(series.count == 4, "series keeps only buckets inside the requested window")
    expect(series.first?.cpu == 36, "series is sorted oldest first")
    expect(series.last?.cpu == 54, "series ends with the newest bucket")
}

func testStatisticsComputeAveragePeakAndMinimum() {
    let points = [
        MetricPoint(date: historyBase, cpu: 10, memory: 40, diskRead: 100, diskWrite: 200, networkReceive: 1_000, networkSend: 2_000),
        MetricPoint(date: historyBase.addingTimeInterval(60), cpu: 30, memory: nil, diskRead: 300, diskWrite: nil, networkReceive: nil, networkSend: nil),
        MetricPoint(date: historyBase.addingTimeInterval(120), cpu: 50, memory: 60, diskRead: 200, diskWrite: 400, networkReceive: 3_000, networkSend: 6_000)
    ]
    let cpu = HistoryAnalyzer.statistics(points, metric: \.cpu)
    expectNear(cpu.average, 30, "cpu statistics average over present values only")
    expectNear(cpu.peak, 50, "cpu statistics peak is the maximum value")
    expectNear(cpu.minimum, 10, "cpu statistics minimum is the smallest value")

    let memory = HistoryAnalyzer.statistics(points, metric: \.memory)
    expectNear(memory.average, 50, "memory statistics skip missing samples")
    let network = HistoryAnalyzer.statistics(points, metric: \.networkReceive)
    expectNear(network.average, 2_000, "network statistics skip missing samples")
    expect(HistoryAnalyzer.statistics([], metric: \.cpu).average == nil, "empty series has no statistics")
}

func testHistoryFileStoreRoundTripsAndToleratesCorruption() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macpulse-history-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HistoryFileStore(directory: directory)
    expect(store.load().isEmpty, "missing history file loads as empty")

    let bucket = MinuteBucket(
        minuteStart: historyBase, sampleCount: 4,
        cpuAverage: 33, cpuPeak: 44,
        memoryAverage: 55, memoryPeak: 66,
        diskReadAverage: 100, diskReadPeak: 200,
        diskWriteAverage: 300, diskWritePeak: 400,
        networkReceiveAverage: 1_000, networkReceivePeak: 2_000,
        networkSendAverage: 3_000, networkSendPeak: 4_000
    )
    expect(store.save([bucket]), "history store saves its buckets")
    expect(store.load() == [bucket], "history store round-trips buckets unchanged")

    try "not json".data(using: .utf8)!.write(to: store.fileURL)
    expect(store.load().isEmpty, "corrupt history file loads as empty instead of crashing")
}

func testDownsampleKeepsWindowBoundsInsteadOfTruncatingHead() {
    let short: [Double?] = [1, nil, 3]
    expect(HistoryAnalyzer.downsample(short, maxPoints: 600) == short, "series shorter than the cap passes through unchanged")

    let values: [Double?] = (0..<12).map { Double($0) }
    let downsampled = HistoryAnalyzer.downsample(values, maxPoints: 4)
    expect(downsampled == [0, 3, 6, 11], "long series is evenly decimated but keeps the newest sample")
    expect(downsampled.last == values.last, "decimation always pins the newest sample to the right edge")
    expect(HistoryAnalyzer.downsample(values, maxPoints: 600).count == 12, "decimation never grows a series")
    expect(HistoryAnalyzer.downsample([nil, 5, nil], maxPoints: 0) == [nil, 5, nil], "non-positive cap passes the series through")
}

func testTrafficStatisticsIntegrateRatesOverSampleSpacing() {
    let points = [
        MetricPoint(date: historyBase, cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: 100, networkSend: 50),
        MetricPoint(date: historyBase.addingTimeInterval(60), cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: 200, networkSend: 50)
    ]
    let stats = HistoryAnalyzer.trafficStatistics(points, sampleSpacing: 60)
    expectNear(stats.receivedBytes, 18_000, "receive total integrates rates across the sampled spacing")
    expectNear(stats.sentBytes, 6_000, "send total integrates rates across the sampled spacing")
    expectNear(stats.receivePeakPerSecond, 200, "receive peak is the maximum sampled rate")
    expectNear(stats.sendPeakPerSecond, 50, "send peak is the maximum sampled rate")
    expectNear(stats.coverageSeconds, 120, "coverage counts every interval that carried data")
}

func testTrafficStatisticsSkipsMissingSamplesWithoutFabricating() {
    let points = [
        MetricPoint(date: historyBase, cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: nil, networkSend: 500),
        MetricPoint(date: historyBase.addingTimeInterval(60), cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: nil, networkSend: nil),
        MetricPoint(date: historyBase.addingTimeInterval(120), cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: 100, networkSend: nil),
        MetricPoint(date: historyBase.addingTimeInterval(180), cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: .nan, networkSend: -5)
    ]
    let stats = HistoryAnalyzer.trafficStatistics(points, sampleSpacing: 60)
    expectNear(stats.receivedBytes, 6_000, "missing receive samples contribute nothing to the total")
    expectNear(stats.sentBytes, 30_000, "missing send samples contribute nothing to the total")
    expectNear(stats.coverageSeconds, 120, "all-nil and non-finite points are excluded from coverage")
}

func testTrafficStatisticsHandlesEmptySeriesAndInvalidSpacing() {
    let empty = HistoryAnalyzer.trafficStatistics([], sampleSpacing: 60)
    expect(empty.receivedBytes == nil, "empty series has no receive total")
    expect(empty.sentBytes == nil, "empty series has no send total")
    expect(empty.coverageSeconds == 0, "empty series covers no time")
    let invalid = HistoryAnalyzer.trafficStatistics([
        MetricPoint(date: historyBase, cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: 100, networkSend: 100)
    ], sampleSpacing: 0)
    expect(invalid.receivedBytes == nil, "non-positive spacing never fabricates a total")
    expect(invalid.coverageSeconds == 0, "non-positive spacing covers no time")
}

func runMetricsHistoryTests() throws {
    testAggregatorEmitsBucketWhenMinuteRolls()
    testAggregatorFlushEmitsPartialBucketWithoutLosingData()
    testMergedBucketsCombinesDuplicateMinutes()
    testPruneRemovesBucketsOutsideRetention()
    testMinuteSeriesFiltersWithinRangeAndSortsAscending()
    testStatisticsComputeAveragePeakAndMinimum()
    try testHistoryFileStoreRoundTripsAndToleratesCorruption()
    testDownsampleKeepsWindowBoundsInsteadOfTruncatingHead()
    testTrafficStatisticsIntegrateRatesOverSampleSpacing()
    testTrafficStatisticsSkipsMissingSamplesWithoutFabricating()
    testTrafficStatisticsHandlesEmptySeriesAndInvalidSpacing()
}
