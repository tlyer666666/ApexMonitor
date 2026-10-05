import Foundation

func testCalculatesCPUAndByteRatesFromCounterDeltas() {
    var calculator = MetricsCalculator()
    _ = calculator.update(.init(
        uptime: 1,
        cpu: .init(user: 20, system: 10, idle: 70, nice: 0),
        memoryUsedBytes: 40,
        memoryTotalBytes: 100,
        diskReadBytes: 100,
        diskWrittenBytes: 200,
        networkReceivedBytes: 1_000,
        networkSentBytes: 2_000
    ))

    let snapshot = calculator.update(.init(
        uptime: 3,
        cpu: .init(user: 30, system: 15, idle: 75, nice: 0),
        memoryUsedBytes: 50,
        memoryTotalBytes: 100,
        diskReadBytes: 1_100,
        diskWrittenBytes: 600,
        networkReceivedBytes: 2_000,
        networkSentBytes: 3_000
    ))

    expectNear(snapshot.cpuPercent, 75, "CPU utilization is derived from cumulative tick deltas")
    expectNear(snapshot.cpuUserPercent, 50, "user tick share is computed from the same deltas")
    expectNear(snapshot.cpuSystemPercent, 25, "system tick share is computed from the same deltas")
    expectNear(snapshot.cpuIdlePercent, 25, "idle tick share is computed from the same deltas")
    expectNear(snapshot.cpuNicePercent, 0, "nice tick share is computed from the same deltas")
    expectNear(snapshot.diskReadBytesPerSecond, 500, "disk read rate divides byte delta by elapsed time")
    expectNear(snapshot.diskWriteBytesPerSecond, 200, "disk write rate divides byte delta by elapsed time")
    expectNear(snapshot.networkReceiveBytesPerSecond, 500, "network receive rate divides byte delta by elapsed time")
    expectNear(snapshot.networkSendBytesPerSecond, 500, "network send rate divides byte delta by elapsed time")
    expectNear(snapshot.memoryPercent, 50, "memory percentage is derived from used and total bytes")
}

func testMultiCoreCPUIsNormalizedToTotalProcessorCapacity() {
    var calculator = MetricsCalculator()
    _ = calculator.update(.init(
        uptime: 10,
        cpu: .init(user: 1_000, system: 1_000, idle: 2_000, nice: 0),
        memoryUsedBytes: 1,
        memoryTotalBytes: 2,
        diskReadBytes: 0,
        diskWrittenBytes: 0,
        networkReceivedBytes: 0,
        networkSentBytes: 0
    ))
    let snapshot = calculator.update(.init(
        uptime: 11,
        cpu: .init(user: 1_050, system: 1_050, idle: 2_100, nice: 0),
        memoryUsedBytes: 1,
        memoryTotalBytes: 2,
        diskReadBytes: 0,
        diskWrittenBytes: 0,
        networkReceivedBytes: 0,
        networkSentBytes: 0
    ))
    expectNear(snapshot.cpuPercent, 50, "two cores each at 50 percent produce a total CPU reading of 50 percent")
}

func testFirstSampleAndCounterResetDoNotInventRates() {
    var calculator = MetricsCalculator()
    let first = calculator.update(.init(
        uptime: 1,
        cpu: .init(user: 4, system: 2, idle: 4, nice: 0),
        memoryUsedBytes: 5,
        memoryTotalBytes: 10,
        diskReadBytes: 100,
        diskWrittenBytes: 100,
        networkReceivedBytes: 100,
        networkSentBytes: 100
    ))
    expect(first.cpuPercent == nil, "first sample does not invent CPU rate")
    expect(first.diskReadBytesPerSecond == nil, "first sample does not invent disk rate")

    let reset = calculator.update(.init(
        uptime: 2,
        cpu: .init(user: 5, system: 3, idle: 5, nice: 0),
        memoryUsedBytes: 5,
        memoryTotalBytes: 10,
        diskReadBytes: 10,
        diskWrittenBytes: 120,
        networkReceivedBytes: 120,
        networkSentBytes: 120
    ))
    expect(reset.diskReadBytesPerSecond == nil, "counter reset invalidates only the reset direction")
    expect(reset.diskWriteBytesPerSecond == 20, "unreset disk counter still yields a valid rate")
}

func testInvalidTimeAndMissingCountersStayUnavailable() {
    var calculator = MetricsCalculator()
    _ = calculator.update(.init(
        uptime: 2,
        cpu: .init(user: 10, system: 10, idle: 80, nice: 0),
        memoryUsedBytes: 5,
        memoryTotalBytes: 10,
        diskReadBytes: 100,
        diskWrittenBytes: 100,
        networkReceivedBytes: 100,
        networkSentBytes: 100
    ))
    let invalidTime = calculator.update(.init(
        uptime: 2,
        cpu: .init(user: 20, system: 10, idle: 80, nice: 0),
        memoryUsedBytes: 5,
        memoryTotalBytes: 10,
        diskReadBytes: 200,
        diskWrittenBytes: 200,
        networkReceivedBytes: 200,
        networkSentBytes: 200
    ))
    expect(invalidTime.cpuPercent == nil, "zero elapsed time does not create CPU rate")
    expect(invalidTime.diskReadBytesPerSecond == nil, "zero elapsed time does not create disk rate")

    let missing = calculator.update(.init(
        uptime: 3,
        cpu: nil,
        memoryUsedBytes: 5,
        memoryTotalBytes: 10,
        diskReadBytes: nil,
        diskWrittenBytes: nil,
        networkReceivedBytes: nil,
        networkSentBytes: nil
    ))
    expectNear(missing.memoryPercent, 50, "valid memory remains visible without disk or network counters")
    expect(missing.cpuPercent == nil, "missing CPU counter remains unavailable")
    expect(missing.diskReadBytesPerSecond == nil, "missing disk counter remains unavailable")
}

func testShrinkingNetworkTotalsNeverFabricateRate() {
    var calculator = MetricsCalculator()
    _ = calculator.update(.init(
        uptime: 1,
        cpu: .init(user: 1, system: 1, idle: 8, nice: 0),
        memoryUsedBytes: 1,
        memoryTotalBytes: 2,
        diskReadBytes: 0,
        diskWrittenBytes: 0,
        networkReceivedBytes: 4_000_000_000,
        networkSentBytes: 100
    ))

    let snapshot = calculator.update(.init(
        uptime: 2,
        cpu: .init(user: 2, system: 2, idle: 16, nice: 0),
        memoryUsedBytes: 1,
        memoryTotalBytes: 2,
        diskReadBytes: 0,
        diskWrittenBytes: 0,
        networkReceivedBytes: 50,
        networkSentBytes: 100
    ))

    expect(snapshot.networkReceiveBytesPerSecond == nil, "shrinking runtime network totals produce no rate instead of a fabricated spike")
}

func testLongSamplingGapRebaselinesInsteadOfReportingOldActivity() {
    func sample(_ time: Double, _ count: UInt64) -> RawMetricsSample {
        .init(uptime: time, cpu: .init(user: count, system: 0, idle: count, nice: 0),
              memoryUsedBytes: 1, memoryTotalBytes: 2, diskReadBytes: count,
              diskWrittenBytes: count, networkReceivedBytes: count, networkSentBytes: count)
    }
    var calculator = MetricsCalculator()
    _ = calculator.update(sample(1, 100))
    let wake = calculator.update(sample(601, 900))
    expect(wake.cpuPercent == nil && wake.networkReceiveBytesPerSecond == nil,
           "long sampling gaps rebaseline instead of reporting sleep as current activity")
    let next = calculator.update(sample(602, 1_000))
    expectNear(next.networkReceiveBytesPerSecond, 100, "sampling resumes normally after a gap")
}

func runMetricsCalculatorTests() {
    testLongSamplingGapRebaselinesInsteadOfReportingOldActivity()
    testCalculatesCPUAndByteRatesFromCounterDeltas()
    testMultiCoreCPUIsNormalizedToTotalProcessorCapacity()
    testFirstSampleAndCounterResetDoNotInventRates()
    testInvalidTimeAndMissingCountersStayUnavailable()
    testShrinkingNetworkTotalsNeverFabricateRate()
}
