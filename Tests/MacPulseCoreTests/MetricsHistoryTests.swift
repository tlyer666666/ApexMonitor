import Foundation

private let historyBase = Date(timeIntervalSince1970: 1_700_006_400)

private func makeSnapshot(cpu: Double?, memory: Double? = 50, diskRead: Double? = 100, diskWrite: Double? = 100, netRx: Double? = 1_000, netTx: Double? = 2_000, duration: Double? = nil) -> MetricsSnapshot {
    MetricsSnapshot(
        timestamp: 0,
        cpuPercent: cpu,
        memoryUsedBytes: memory == nil ? nil : 1,
        memoryTotalBytes: memory == nil ? nil : 2,
        memoryPercent: memory,
        diskReadBytesPerSecond: diskRead,
        diskWriteBytesPerSecond: diskWrite,
        networkReceiveBytesPerSecond: netRx,
        networkSendBytesPerSecond: netTx,
        sampleDurationSeconds: duration
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

private func trafficBucket(_ rates: [Double?], offset: Double = 0, start: Date = historyBase) -> MinuteBucket {
    var aggregator = MetricsAggregator()
    for (index, rate) in rates.enumerated() {
        _ = aggregator.append(
            makeSnapshot(cpu: rate, memory: nil, diskRead: rate, diskWrite: nil, netRx: rate, netTx: nil),
            at: start.addingTimeInterval(offset + Double(index))
        )
    }
    return aggregator.flush(at: start.addingTimeInterval(60))!
}

private func bucketTraffic(_ buckets: [MinuteBucket]) -> TrafficStatistics {
    HistoryAnalyzer.trafficStatistics(
        HistoryAnalyzer.minuteSeries(from: buckets, within: 300, now: historyBase.addingTimeInterval(61)),
        sampleSpacing: 60
    )
}

func testPartialMinuteTrafficUsesOnlyObservedSeconds() {
    let stats = bucketTraffic([trafficBucket([100], offset: 30)])
    expectNear(stats.receivedBytes, 100, "one 100 B/s sample contributes 100 bytes, not a whole minute")
    expectNear(stats.coverageSeconds, 1, "a partial minute preserves its one second of valid coverage")
}

func testMissingRatesDoNotIncreaseMinuteTrafficCoverage() {
    let bucket = trafficBucket(Array(repeating: nil, count: 59) + [100])
    let stats = bucketTraffic([bucket])
    expect(bucket.sampleCount == 60, "the missing-rate fixture still contains sixty snapshots")
    expectNear(stats.receivedBytes, 100, "fifty-nine missing rates do not fabricate received bytes")
    expectNear(stats.coverageSeconds, 1, "fifty-nine missing rates do not fabricate valid seconds")
}

func testFragmentMergeUsesPerMetricValidCountsInAnyOrder() {
    let first = trafficBucket([nil, 100])
    let second = trafficBucket([0], offset: 2)
    for fragments in [[first, second], [second, first]] {
        let merged = HistoryAnalyzer.mergedBuckets(fragments)[0]
        expectNear(merged.networkReceiveAverage, 50, "fragment receive mean uses two valid values, not three snapshots")
        expectNear(merged.cpuAverage, 50, "fragment cpu mean uses its own valid count")
        expectNear(merged.diskReadAverage, 50, "fragment disk mean uses its own valid count")
        expectNear(bucketTraffic([merged]).receivedBytes, 100, "fragment merging conserves integrated traffic bytes")
    }
    let a = trafficBucket([nil])
    let b = trafficBucket([100], offset: 1)
    let c = trafficBucket([0], offset: 2)
    for fragments in [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]] {
        let merged = HistoryAnalyzer.mergedBuckets(fragments)[0]
        expectNear(merged.networkReceiveAverage, 50, "nil-containing fragment merge is permutation independent")
    }
}

func testMinuteStatisticsKeepSamplePeakWithoutChangingChartMean() {
    let bucket = trafficBucket([6_000] + Array(repeating: 0, count: 59))
    let points = HistoryAnalyzer.minuteSeries(from: [bucket], within: 300, now: historyBase.addingTimeInterval(61))
    expectNear(points.first?.networkReceive, 100, "minute chart still plots the 100 B/s mean")
    expectNear(HistoryAnalyzer.trafficStatistics(points, sampleSpacing: 60).receivePeakPerSecond, 6_000,
               "traffic summary reports the sampled 6000 B/s peak")
    expectNear(HistoryAnalyzer.statistics(points, metric: \.networkReceive).peak, 6_000,
               "generic minute statistics retain the original sampled peak")
    expectNear(HistoryAnalyzer.statistics(points, metric: \.cpu).peak, 6_000,
               "sampled peaks propagate for non-network metrics too")
}

func testLegacyJSONDoesNotInventTrafficCoverage() throws {
    let json = """
    [{"minuteStart":"2023-11-15T00:00:00Z","sampleCount":60,
      "networkReceiveAverage":100,"networkReceivePeak":1000}]
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let buckets = try decoder.decode([MinuteBucket].self, from: Data(json.utf8))
    expectNear(buckets.first?.networkReceiveAverage, 100, "history-v1 averages remain readable")
    let stats = bucketTraffic(buckets)
    expect(stats.receivedBytes == nil, "legacy minute averages cannot establish a received byte total")
    expect(stats.sentBytes == nil, "legacy minute averages cannot establish a sent byte total")
    expectNear(stats.coverageSeconds, 0, "legacy history has unknown, not sixty-second, coverage")
    expectNear(stats.receivePeakPerSecond, 1_000, "legacy history can still supply its recorded peak")
}

func testNewHistoryMetadataRoundTrips() throws {
    let bucket = trafficBucket([100], offset: 30)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode([bucket])
    let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    let metadata = objects?.first?["metadata"] as? [String: Any]
    let receive = metadata?["networkReceive"] as? [String: Any]
    expect(metadata != nil, "new history persists optional aggregation metadata")
    expect(receive?["validCount"] as? Int == 1, "persisted receive metadata retains its valid sample count")
    expectNear(receive?["validDurationSeconds"] as? Double, 1, "persisted receive metadata retains actual duration")
    expectNear(receive?["totalBytes"] as? Double, 100, "persisted receive metadata retains integrated bytes")
    expectNear(receive?["samplePeak"] as? Double, 100, "persisted receive metadata retains sampled peak")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([MinuteBucket].self, from: data)
    expect(decoded == [bucket], "new aggregation metadata round-trips unchanged")
    expectNear(bucketTraffic(decoded).receivedBytes, 100, "round-tripped partial-minute traffic stays exact")
    expectNear(bucketTraffic(decoded).coverageSeconds, 1, "round-tripped partial-minute coverage stays exact")
}

func testPruningExcludesFutureBucketsAndDownsampleKeepsBothEnds() {
    let present = trafficBucket([100])
    let future = trafficBucket([100], start: historyBase.addingTimeInterval(60))
    expect(HistoryAnalyzer.prunedBuckets([present, future], now: historyBase) == [present],
           "clock rollback pruning excludes future minute buckets")
    expect(HistoryAnalyzer.downsample([1, 2, 3, 4, 5], maxPoints: 2) == [1, 5],
           "two-point downsampling retains both endpoints")
}

func testActualDurationsIntegrateIndependentlyOfSpacingAndCounts() throws {
    var aggregator = MetricsAggregator()
    let first = makeSnapshot(cpu: 10, memory: nil, diskRead: 100, diskWrite: nil, netRx: 100, netTx: nil, duration: 2.5)
    let second = makeSnapshot(cpu: nil, memory: 40, diskRead: nil, diskWrite: 200, netRx: nil, netTx: 200, duration: 0.5)
    _ = aggregator.append(first, at: historyBase.addingTimeInterval(10.25))
    _ = aggregator.append(second, at: historyBase.addingTimeInterval(10.75))
    let bucket = aggregator.flush(at: historyBase.addingTimeInterval(11))!
    let metadata = bucket.metadata!
    expect(metadata.cpu.validCount == 1 && metadata.memory.validCount == 1, "each gauge retains its independent valid count")
    expect(metadata.diskRead.validCount == 1 && metadata.diskWrite.validCount == 1, "each disk direction retains its independent valid count")
    expectNear(metadata.networkReceive.validDurationSeconds, 2.5, "receive duration is measured, not snapshot count")
    expectNear(metadata.networkSend.validDurationSeconds, 0.5, "send duration is measured independently")
    expectNear(metadata.diskRead.totalBytes, 250, "disk reads integrate the actual 2.5-second interval")
    expectNear(metadata.diskWrite.totalBytes, 100, "disk writes integrate their actual half-second interval")
    let stats = bucketTraffic([bucket])
    expectNear(stats.receivedBytes, 250, "100 B/s over 2.5 seconds integrates to 250 bytes")
    expectNear(stats.sentBytes, 100, "200 B/s over half a second integrates to 100 bytes")
    expectNear(stats.coverageSeconds, 3, "disjoint receive/send sample intervals contribute their union")
    expect(!stats.isEstimated && !stats.hasLegacyGaps, "a fully contained measured fragment reports exact known coverage")
    let raw = MetricPoint(date: historyBase.addingTimeInterval(10.25), snapshot: first)
    let rawStats = HistoryAnalyzer.trafficStatistics([raw], sampleSpacing: 60)
    expectNear(rawStats.receivedBytes, 250, "snapshot points ignore nominal spacing when actual duration exists")
    expectNear(rawStats.coverageSeconds, 2.5, "snapshot points retain actual coverage")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(MinuteBucket.self, from: encoder.encode(bucket))
    expect(decoded == bucket, "fractional interval boundaries survive ISO8601 bucket persistence")
}

func testInvalidDurationsAndRatesNeverCreateTraffic() {
    for duration in [0.0, -1, Double.nan, Double.infinity] {
        var aggregator = MetricsAggregator()
        let snapshot = makeSnapshot(cpu: 10, netRx: 100, netTx: 200, duration: duration)
        _ = aggregator.append(snapshot, at: historyBase.addingTimeInterval(30))
        let bucket = aggregator.flush(at: historyBase.addingTimeInterval(31))!
        let stats = bucketTraffic([bucket])
        expect(stats.receivedBytes == nil && stats.sentBytes == nil, "invalid durations cannot integrate traffic")
        expectNear(stats.coverageSeconds, 0, "invalid durations supply no covered time")
        expect(bucket.metadata?.networkReceive.validCount == 0, "invalid rate intervals have zero valid observations")
        expectNear(bucket.cpuAverage, 10, "invalid rate duration does not hide a valid gauge")
    }
    let invalidRates = bucketTraffic([trafficBucket([nil, .nan, .infinity, -1])])
    expect(invalidRates.receivedBytes == nil, "nonfinite and negative rates cannot create persisted traffic")
    expectNear(invalidRates.coverageSeconds, 0, "invalid rates cannot inflate persisted coverage")
    let zero = bucketTraffic([trafficBucket([0])])
    expectNear(zero.receivedBytes, 0, "measured zero traffic is distinct from unknown traffic")
    expectNear(zero.coverageSeconds, 1, "measured idle intervals still provide coverage")
    let both = MetricPoint(date: historyBase, snapshot: makeSnapshot(cpu: nil, netRx: 100, netTx: 200, duration: 2))
    expectNear(HistoryAnalyzer.trafficStatistics([both], sampleSpacing: 60).coverageSeconds, 2,
               "simultaneous receive/send directions do not double-count coverage")
}

func testLegacyFlagsAndMixedMergesSurvivePersistence() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let legacy = try decoder.decode(MinuteBucket.self, from: Data("""
    {"minuteStart":"2023-11-15T00:00:00Z","sampleCount":60,
     "networkReceiveAverage":100,"networkReceivePeak":1000}
    """.utf8))
    expect(legacy.metadata == nil, "missing optional metadata remains a decodable legacy bucket")
    let legacyStats = bucketTraffic([legacy])
    expect(legacyStats.hasLegacyGaps && legacyStats.isEstimated, "legacy coverage limitations are explicitly exposed")
    let exact = trafficBucket([50], offset: 30)
    let first = HistoryAnalyzer.mergedBuckets([legacy, exact])[0]
    let reverse = HistoryAnalyzer.mergedBuckets([exact, legacy])[0]
    expect(first == reverse, "legacy/new fragments retain identical metadata in either order")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoded = try decoder.decode(MinuteBucket.self, from: encoder.encode(first))
    let stats = bucketTraffic([decoded])
    expectNear(stats.receivedBytes, 50, "mixed histories retain only the fifty known bytes")
    expectNear(stats.coverageSeconds, 1, "mixed histories retain only the one known second")
    expect(stats.hasLegacyGaps && stats.isEstimated, "legacy gaps cannot disappear through merge and roundtrip")
    expectNear(stats.receivePeakPerSecond, 1000, "known legacy sample peaks remain available after merging")
    let raw = MetricPoint(date: historyBase, cpu: nil, memory: nil, diskRead: nil, diskWrite: nil, networkReceive: 10, networkSend: nil)
    expect(HistoryAnalyzer.trafficStatistics([raw], sampleSpacing: 60).isEstimated,
           "spacing-only integration is explicitly marked estimated")
}

func testWindowClippingMarksEstimatedButWholeObservedSpansAreExact() {
    let bucket = trafficBucket(Array(repeating: 100, count: 60)) // measured span [-1, 59]
    let full = HistoryAnalyzer.minuteSeries(from: [bucket], within: 60, now: historyBase.addingTimeInterval(59))
    let fullStats = HistoryAnalyzer.trafficStatistics(full, sampleSpacing: 60)
    expectNear(fullStats.receivedBytes, 6000, "a whole observed span keeps all integrated bytes")
    expectNear(fullStats.coverageSeconds, 60, "a whole observed span keeps all covered seconds")
    expect(!fullStats.isEstimated, "a complete observed span need not be marked estimated")
    let clipped = HistoryAnalyzer.minuteSeries(from: [bucket], within: 30, now: historyBase.addingTimeInterval(59))
    let clippedStats = HistoryAnalyzer.trafficStatistics(clipped, sampleSpacing: 60)
    expect(clipped.count == 1, "a bucket overlapping the lower range boundary is not discarded")
    expectNear(clippedStats.receivedBytes, 3000, "a half-span constant-rate fixture prorates to 3000 bytes")
    expectNear(clippedStats.coverageSeconds, 30, "boundary proration never claims a full minute")
    expect(clippedStats.isEstimated, "partial-bucket integrals cannot claim exactness without individual samples")
    expect(HistoryAnalyzer.statistics(clipped, metric: \.networkReceive).isEstimated,
           "a peak from a partially clipped bucket also exposes uncertainty")
    let upper = HistoryAnalyzer.minuteSeries(from: [bucket], within: 120, now: historyBase.addingTimeInterval(29))
    expect(HistoryAnalyzer.trafficStatistics(upper, sampleSpacing: 60).isEstimated,
           "clipping at now after a clock rollback also exposes uncertainty")
    expect(HistoryAnalyzer.minuteSeries(from: [bucket], within: 0, now: historyBase).isEmpty,
           "nonpositive range cannot produce fabricated history")
}

func testFragmentMetadataMergeIsAssociativeForNonoverlappingSamples() {
    let a = trafficBucket([nil, 100], offset: 10)
    let b = trafficBucket([0], offset: 12)
    let c = trafficBucket([200], offset: 13)
    let combined = HistoryAnalyzer.mergedBuckets([a, b, c])[0]
    let nested = HistoryAnalyzer.mergedBuckets([a, HistoryAnalyzer.mergedBuckets([b, c])[0]])[0]
    expect(combined == nested, "sufficient statistics survive nested fragment merging")
    expect(combined.metadata?.networkReceive.validCount == 3, "merged receive valid count excludes nil observations")
    expectNear(combined.networkReceiveAverage, 100, "three valid fragment samples average to 100")
    expectNear(bucketTraffic([combined]).receivedBytes, 300, "fragment merge conserves three hundred known bytes")
    expectNear(bucketTraffic([combined]).coverageSeconds, 3, "fragment merge conserves three valid seconds")
}

func testCurrentBucketPreviewDoesNotConsumeOrDuplicateSamples() {
    var aggregator = MetricsAggregator()
    expect(aggregator.currentBucket == nil, "empty aggregator has no preview bucket")
    _ = aggregator.append(makeSnapshot(cpu: 10, netRx: 100, netTx: nil), at: historyBase.addingTimeInterval(10))
    let preview = aggregator.currentBucket
    expect(preview?.sampleCount == 1, "current bucket previews the pending sample")
    expect(aggregator.currentBucket == preview, "repeated current-bucket reads do not mutate aggregation")
    _ = aggregator.append(makeSnapshot(cpu: 30, netRx: 300, netTx: nil), at: historyBase.addingTimeInterval(11))
    expect(aggregator.currentBucket?.sampleCount == 2, "append continues the same bucket after preview")
    expectNear(aggregator.currentBucket?.metadata?.networkReceive.totalBytes, 400, "preview does not duplicate integrated bytes")
    let flushed = aggregator.flush(at: historyBase.addingTimeInterval(12))
    expect(flushed?.sampleCount == 2, "flush still emits every previewed sample exactly once")
    expect(aggregator.currentBucket == nil, "flush clears the preview")
    _ = aggregator.append(makeSnapshot(cpu: 50), at: historyBase.addingTimeInterval(20))
    let completed = aggregator.append(makeSnapshot(cpu: 60), at: historyBase.addingTimeInterval(61))
    expectNear(completed?.cpuAverage, 50, "minute rollover still emits the preceding bucket after preview")
    expectNear(aggregator.currentBucket?.cpuAverage, 60, "preview follows the new minute after rollover")
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
    testPartialMinuteTrafficUsesOnlyObservedSeconds()
    testMissingRatesDoNotIncreaseMinuteTrafficCoverage()
    testFragmentMergeUsesPerMetricValidCountsInAnyOrder()
    testMinuteStatisticsKeepSamplePeakWithoutChangingChartMean()
    try testLegacyJSONDoesNotInventTrafficCoverage()
    try testNewHistoryMetadataRoundTrips()
    testPruningExcludesFutureBucketsAndDownsampleKeepsBothEnds()
    try testActualDurationsIntegrateIndependentlyOfSpacingAndCounts()
    testInvalidDurationsAndRatesNeverCreateTraffic()
    try testLegacyFlagsAndMixedMergesSurvivePersistence()
    testWindowClippingMarksEstimatedButWholeObservedSpansAreExact()
    testFragmentMetadataMergeIsAssociativeForNonoverlappingSamples()
    testCurrentBucketPreviewDoesNotConsumeOrDuplicateSamples()
}
