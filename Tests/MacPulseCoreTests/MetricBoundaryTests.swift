import Foundation

func testDecodesHighBitProcessorTicksWithoutSignedOverflow() {
    expect(
        MetricCounter.unsignedValue(fromSigned32: Int32(bitPattern: 0xF000_0000)) == 4_026_531_840,
        "high-bit Mach tick is decoded as its unsigned cumulative value"
    )
}

func testMemoryTrendGeometryHandlesEmptySinglePointAndFlatValues() {
    expect(MemoryTrendGeometry.normalizedPoints(for: []).isEmpty, "empty memory history produces no geometry")

    let single = MemoryTrendGeometry.normalizedPoints(for: [50])
    expect(single.count == 1, "single memory sample produces one point")
    if let point = single.first {
        expect(point.x.isFinite && point.y.isFinite, "single memory sample produces finite coordinates")
        expectNear(point.x, 0.5, "single memory sample is centered horizontally")
    }

    let flat = MemoryTrendGeometry.normalizedPoints(for: [50, 50, 50])
    expect(flat.count == 3, "flat history keeps all samples")
    expect(flat.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "flat history produces finite coordinates")
}

func testNetworkCounterAccumulatorKeepsTotalsMonotonicWhenInterfaceDeparts() {
    var accumulator = NetworkCounterAccumulator()
    _ = accumulator.update([
        "en0": .init(receivedBytes: 1_000, sentBytes: 500),
        "utun0": .init(receivedBytes: 10_000, sentBytes: 5_000)
    ])

    let established = accumulator.update([
        "en0": .init(receivedBytes: 1_500, sentBytes: 750),
        "utun0": .init(receivedBytes: 10_400, sentBytes: 5_200)
    ])
    expect(established?.receivedBytes == 900, "both interfaces contribute deltas while present")
    expect(established?.sentBytes == 450, "both interfaces contribute deltas while present")

    let afterDeparture = accumulator.update([
        "en0": .init(receivedBytes: 1_500, sentBytes: 750)
    ])
    expect(afterDeparture?.receivedBytes == 900, "departed interface's accumulated bytes stay in the totals")
    expect(afterDeparture?.sentBytes == 450, "departed interface's accumulated bytes stay in the totals")

    let afterRejoin = accumulator.update([
        "en0": .init(receivedBytes: 1_600, sentBytes: 800),
        "utun0": .init(receivedBytes: 100, sentBytes: 50)
    ])
    expect(afterRejoin?.receivedBytes == 1_000, "rejoined interface establishes a fresh baseline without double counting")
    expect(afterRejoin?.sentBytes == 500, "rejoined interface establishes a fresh baseline without double counting")
}

func runMetricBoundaryTests() {
    testDecodesHighBitProcessorTicksWithoutSignedOverflow()
    testMemoryTrendGeometryHandlesEmptySinglePointAndFlatValues()
}

func testNetworkCounterAccumulatorUnwrapsEachInterfaceBeforeSumming() {
    var accumulator = NetworkCounterAccumulator()
    _ = accumulator.update([
        "en0": .init(receivedBytes: UInt64(UInt32.max) - 100, sentBytes: UInt64(UInt32.max) - 50),
        "utun0": .init(receivedBytes: 4_000_000_000, sentBytes: 4_000_000_000)
    ])

    let totals = accumulator.update([
        "en0": .init(receivedBytes: 50, sentBytes: 25),
        "utun0": .init(receivedBytes: 4_000_000_100, sentBytes: 4_000_000_050)
    ])

    expect(totals?.receivedBytes == 251, "each interface's receive wrap is expanded before totals are summed")
    expect(totals?.sentBytes == 126, "each interface's send wrap is expanded before totals are summed")
}

func testNetworkCounterAccumulatorDoesNotTurnOrdinaryResetIntoTraffic() {
    var accumulator = NetworkCounterAccumulator()
    _ = accumulator.update([
        "en0": .init(receivedBytes: 5_000, sentBytes: 2_000),
        "utun0": .init(receivedBytes: 10_000, sentBytes: 3_000)
    ])

    let totals = accumulator.update([
        "en0": .init(receivedBytes: 25, sentBytes: 10),
        "utun0": .init(receivedBytes: 10_050, sentBytes: 3_025)
    ])

    expect(totals?.receivedBytes == 50, "ordinary receive reset contributes no artificial four-gibibyte burst")
    expect(totals?.sentBytes == 25, "ordinary send reset contributes no artificial four-gibibyte burst")
}
