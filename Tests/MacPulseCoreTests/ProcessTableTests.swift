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

func runProcessTableTests() {
    testFirstProcessSampleRanksByMemoryWithoutInventingCPU()
    testSecondProcessSampleComputesCPUPercentFromWallTime()
    testProcessCounterResetAndInvalidTimeDoNotInventCPU()
    testProcessListIsBoundedAndDepartedPIDsDisappear()
}
