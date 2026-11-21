import Foundation

private func makeProcess(_ pid: Int32, _ name: String, rss: UInt64, cpuNs: UInt64) -> RawProcessSample {
    RawProcessSample(pid: pid, name: name, residentBytes: rss, cpuTimeNanoseconds: cpuNs)
}

func testFirstProcessSampleRanksByMemoryWithoutInventingCPU() {
    var table = ProcessTable()
    let summary = table.update([
        makeProcess(101, "Safari", rss: 300, cpuNs: 0),
        makeProcess(102, "WindowServer", rss: 500, cpuNs: 0)
    ], at: 0)

    expect(summary.processCount == 2, "process count reflects the sampled process list")
    expect(summary.topByMemory.map(\.name) == ["WindowServer", "Safari"], "memory ranking sorts by resident bytes")
    expect(summary.topByMemory.allSatisfy { $0.cpuPercent == nil }, "first sample has no CPU baseline yet")
}

func testSecondProcessSampleComputesCPUPercentFromWallTime() {
    var table = ProcessTable()
    _ = table.update([
        makeProcess(101, "Safari", rss: 300, cpuNs: 1_000_000_000),
        makeProcess(102, "mds", rss: 100, cpuNs: 0)
    ], at: 10)

    let summary = table.update([
        makeProcess(101, "Safari", rss: 320, cpuNs: 2_000_000_000),
        makeProcess(102, "mds", rss: 100, cpuNs: 400_000_000)
    ], at: 12)

    let safari = summary.topByCPU.first { $0.pid == 101 }
    let mds = summary.topByCPU.first { $0.pid == 102 }
    expectNear(safari?.cpuPercent, 50, "process CPU percent divides CPU-time delta by wall-time delta")
    expectNear(mds?.cpuPercent, 20, "process CPU percent normalizes to one core")
    expect(summary.topByCPU.first?.pid == 101, "CPU ranking orders by computed percent")
    expect(summary.topByMemory.first?.pid == 101, "memory ranking follows the newest resident sizes")
}

func testProcessCounterResetAndInvalidTimeDoNotInventCPU() {
    var table = ProcessTable()
    _ = table.update([
        makeProcess(201, "A", rss: 100, cpuNs: 2_000_000_000)
    ], at: 10)

    // Shrinking CPU time (pid reuse or counter reset) resets the baseline.
    let reset = table.update([
        makeProcess(201, "A", rss: 100, cpuNs: 1_000_000_000)
    ], at: 11)
    expect(reset.topByCPU.allSatisfy { $0.cpuPercent == nil }, "shrinking process CPU time re-baselines instead of fabricating")

    // Zero elapsed time yields no CPU percent.
    _ = table.update([
        makeProcess(201, "A", rss: 100, cpuNs: 1_500_000_000)
    ], at: 11)
    let invalid = table.update([
        makeProcess(201, "A", rss: 100, cpuNs: 1_600_000_000)
    ], at: 11)
    expect(invalid.topByCPU.allSatisfy { $0.cpuPercent == nil }, "zero elapsed time does not create process CPU rate")
}

func testProcessListIsBoundedAndDepartedPIDsDisappear() {
    var table = ProcessTable()
    let first = (300..<312).map { pid in
        makeProcess(Int32(pid), "p\(pid)", rss: UInt64(pid), cpuNs: 0)
    }
    _ = table.update(first, at: 0)
    let second = (300..<312).map { pid in
        makeProcess(Int32(pid), "p\(pid)", rss: UInt64(pid), cpuNs: UInt64(pid) * 1_000_000)
    }
    let summary = table.update(second, at: 1)

    expect(summary.topByCPU.count == 10 && summary.topByMemory.count == 10, "top lists are capped at 10 entries")
    expect(summary.topByCPU.first?.pid == 311, "highest CPU consumer leads the list")
    expect(summary.processCount == 12, "process count is not capped by the top list size")

    let departed = table.update([
        makeProcess(300, "p300", rss: 300, cpuNs: 300_000_000)
    ], at: 2)
    expect(departed.processCount == 1, "departed processes leave the sampled list")
    expect(departed.topByMemory.first?.pid == 300, "remaining processes still rank correctly")
}

func testChangedStartIdentityRebaselinesEvenWhenPIDNameAndCounterLookContinuous() {
    let oldStart = ProcessStartIdentity(seconds: 100, microseconds: 10)
    // The microseconds alone can distinguish two incarnations in one second.
    let newStart = ProcessStartIdentity(seconds: 100, microseconds: 11)
    var table = ProcessTable()
    _ = table.update([
        RawProcessSample(pid: 401, name: "worker", residentBytes: 100,
                         cpuTimeNanoseconds: 100_000_000, startIdentity: oldStart)
    ], at: 10)
    let reused = table.update([
        RawProcessSample(pid: 401, name: "worker", residentBytes: 200,
                         cpuTimeNanoseconds: 500_000_000, startIdentity: newStart)
    ], at: 11)
    expect(reused.topByCPU.first?.cpuPercent == nil,
           "changed start identity re-baselines the same PID/name despite a growing CPU counter")
    expect(reused.topByMemory.first?.residentBytes == 200,
           "replacement process still contributes its current resident bytes")

    let stable = table.update([
        RawProcessSample(pid: 401, name: "worker", residentBytes: 200,
                         cpuTimeNanoseconds: 1_500_000_000, startIdentity: newStart)
    ], at: 13)
    expectNear(stable.topByCPU.first?.cpuPercent, 50,
               "stable replacement identity uses nanoseconds over monotonic uptime seconds")

    let laterStart = table.update([
        RawProcessSample(pid: 401, name: "worker", residentBytes: 200,
                         cpuTimeNanoseconds: 2_000_000_000,
                         startIdentity: ProcessStartIdentity(seconds: 101, microseconds: 11))
    ], at: 14)
    expect(laterStart.topByCPU.first?.cpuPercent == nil,
           "start identity compares seconds as well as microseconds")
}

func testStableIdentityCounterResetAndUptimeRollbackRebaseline() {
    let identity = ProcessStartIdentity(seconds: 100, microseconds: 20)
    func sample(_ cpu: UInt64) -> RawProcessSample {
        RawProcessSample(pid: 402, name: "worker", residentBytes: 100,
                         cpuTimeNanoseconds: cpu, startIdentity: identity)
    }
    var table = ProcessTable()
    _ = table.update([sample(2_000_000_000)], at: 10)
    let reset = table.update([sample(1_000_000_000)], at: 11)
    expect(reset.topByCPU.first?.cpuPercent == nil,
           "shrinking CPU counter still re-baselines an unchanged start identity")
    let recovered = table.update([sample(1_500_000_000)], at: 12)
    expectNear(recovered.topByCPU.first?.cpuPercent, 50,
               "stable identity recovers from the reset baseline")
    let rollback = table.update([sample(1_600_000_000)], at: 11)
    expect(rollback.topByCPU.first?.cpuPercent == nil,
           "non-monotonic uptime cannot produce a process CPU rate")
}

func testOptionalStartIdentityPreservesLegacyCallsButRebaselinesTransitions() {
    let legacy = RawProcessSample(pid: 403, name: "worker", residentBytes: 100,
                                  cpuTimeNanoseconds: 0)
    expect(legacy.startIdentity == nil, "legacy sample construction defaults start identity to nil")
    var table = ProcessTable()
    _ = table.update([legacy], at: 10)
    let legacyDelta = table.update([
        RawProcessSample(pid: 403, name: "worker", residentBytes: 100,
                         cpuTimeNanoseconds: 1_000_000_000)
    ], at: 11)
    expectNear(legacyDelta.topByCPU.first?.cpuPercent, 100,
               "two legacy samples retain their existing CPU delta behavior")
    let identified = table.update([
        RawProcessSample(pid: 403, name: "worker", residentBytes: 100,
                         cpuTimeNanoseconds: 2_000_000_000,
                         startIdentity: ProcessStartIdentity(seconds: 100, microseconds: 30))
    ], at: 12)
    expect(identified.topByCPU.first?.cpuPercent == nil,
           "gaining a start identity establishes a fresh baseline")
    let unidentified = table.update([
        RawProcessSample(pid: 403, name: "worker", residentBytes: 100,
                         cpuTimeNanoseconds: 3_000_000_000)
    ], at: 13)
    expect(unidentified.topByCPU.first?.cpuPercent == nil,
           "losing a start identity does not compare counters across unknown incarnations")
}

func testProcessSummaryDisplayOrderSortsByColumnWithStableTies() {
    func stat(_ pid: Int32, _ name: String, cpu: Double?, memory: UInt64) -> ProcessStat {
        ProcessStat(pid: pid, name: name, cpuPercent: cpu, residentBytes: memory)
    }
    let summary = ProcessSummary(
        processCount: 12,
        topByCPU: [
            stat(2, "browser", cpu: 50, memory: 100),
            stat(1, "app", cpu: 10, memory: 900),
            stat(3, "helper", cpu: nil, memory: 50)
        ],
        topByMemory: [
            stat(1, "app", cpu: 10, memory: 900),
            stat(4, "daemon", cpu: 70, memory: 400),
            stat(2, "browser", cpu: 50, memory: 100)
        ]
    )

    let memoryDescending = summary.displayOrder(ProcessSortOrder(column: .memory, ascending: false)).map(\.pid)
    expect(memoryDescending == [1, 4, 2, 3], "memory descending dedupes the union and ranks high to low")
    let memoryAscending = summary.displayOrder(ProcessSortOrder(column: .memory, ascending: true)).map(\.pid)
    expect(memoryAscending == [3, 2, 4, 1], "memory ascending reverses the ranking")

    let cpuDescending = summary.displayOrder(ProcessSortOrder(column: .cpu, ascending: false)).map(\.pid)
    expect(cpuDescending == [4, 2, 1, 3], "cpu descending ranks known values first and unknown last")
    let cpuAscending = summary.displayOrder(ProcessSortOrder(column: .cpu, ascending: true)).map(\.pid)
    expect(cpuAscending == [1, 2, 4, 3], "cpu ascending keeps unknown values last as well")

    let nameAscending = summary.displayOrder(ProcessSortOrder(column: .name, ascending: true)).map(\.pid)
    expect(nameAscending == [1, 2, 4, 3], "name ascending sorts alphabetically (app, browser, daemon, helper)")
}

func testProcessSummaryDisplayOrderKeepsMemoryDefaultEqualToTopByMemory() {
    var table = ProcessTable()
    var samples: [RawProcessSample] = []
    for index in 0..<12 {
        samples.append(RawProcessSample(
            pid: Int32(600 + index),
            name: "proc\(index)",
            residentBytes: UInt64(1_000 + index * 500),
            cpuTimeNanoseconds: UInt64(index) * 40_000_000,
            startIdentity: ProcessStartIdentity(seconds: 100, microseconds: 0)
        ))
    }
    _ = table.update(samples, at: 10)
    let summary = table.update(samples.map {
        RawProcessSample(pid: $0.pid, name: $0.name, residentBytes: $0.residentBytes,
                         cpuTimeNanoseconds: $0.cpuTimeNanoseconds + 30_000_000 + UInt64($0.pid - 600) * 20_000_000,
                         startIdentity: $0.startIdentity)
    }, at: 11)

    let displayed = summary.displayOrder(ProcessSortOrder(column: .memory, ascending: false))
    expect(displayed == summary.topByMemory,
           "the memory page's default display order is exactly the memory ranking")
    let byCPU = summary.displayOrder(ProcessSortOrder(column: .cpu, ascending: false))
    expect(Array(byCPU.prefix(ProcessTable.topLimit)) == summary.topByCPU,
           "switching to CPU ranking reproduces the CPU top list")
}

func runProcessTableTests() {
    testFirstProcessSampleRanksByMemoryWithoutInventingCPU()
    testSecondProcessSampleComputesCPUPercentFromWallTime()
    testProcessCounterResetAndInvalidTimeDoNotInventCPU()
    testProcessListIsBoundedAndDepartedPIDsDisappear()
    testChangedStartIdentityRebaselinesEvenWhenPIDNameAndCounterLookContinuous()
    testStableIdentityCounterResetAndUptimeRollbackRebaseline()
    testOptionalStartIdentityPreservesLegacyCallsButRebaselinesTransitions()
    testProcessSummaryDisplayOrderSortsByColumnWithStableTies()
    testProcessSummaryDisplayOrderKeepsMemoryDefaultEqualToTopByMemory()
}
