import Foundation
#if canImport(MacPulseCore)
import MacPulseCore
#endif

func testFormatsMetricUnitsAndUnavailableValues() {
    expect(MetricsFormatter.cpuPercent(12.6) == "13%", "CPU percentage rounds to an integer")
    expect(MetricsFormatter.bytes(1_610_612_736 as UInt64?) == "1.5 GB", "memory uses binary units with one decimal place")
    expect(MetricsFormatter.bytesPerSecond(1_572_864) == "1.5 MB/s", "rate uses binary units per second")
    expect(MetricsFormatter.bytesPerSecond(nil) == "—", "unavailable rates use an em dash")
}

func testFormatsMemoryUsedAndTotalTogether() {
    expect(
        MetricsFormatter.memorySummary(usedBytes: 1_610_612_736, totalBytes: 2_147_483_648) == "1.5 GB / 2 GB",
        "memory summary shows used bytes before physical total"
    )
    expect(
        MetricsFormatter.memorySummary(usedBytes: nil, totalBytes: 2_147_483_648) == "物理内存",
        "memory summary uses a stable label when a counter is missing"
    )
}

func testFormatsCoverageDurationAndDoubleByteTotals() {
    expect(MetricsFormatter.duration(45) == "45 秒", "durations under a minute show seconds")
    expect(MetricsFormatter.duration(90) == "2 分钟", "durations under an hour show whole minutes")
    expect(MetricsFormatter.duration(3_600) == "1.0 小时", "durations at an hour switch to hours")
    expect(MetricsFormatter.duration(5_400) == "1.5 小时", "hour durations keep one decimal")
    expect(MetricsFormatter.duration(nil) == "—", "missing durations use an em dash")
    expect(MetricsFormatter.bytes(1_572_864.4 as Double?) == "1.5 MB", "double byte totals round to binary units")
    expect(MetricsFormatter.bytes(nil as Double?) == "—", "missing byte totals use an em dash")
}

func testPercentFormattingRejectsInvalidValues() {
    expect(MetricsFormatter.percent(-1) == "—", "negative usage is unavailable, not a negative percentage")
    expect(MetricsFormatter.cpuPercent(-1) == "—", "CPU formatting rejects negative usage")
    expect(MetricsFormatter.percent(.infinity) == "—", "infinite usage stays unavailable")
    expect(MetricsFormatter.percent(250) == "250%", "process CPU above one core stays representable")
    expect(MetricsFormatter.percent(1e20) == "—", "huge finite percentages cannot trap integer conversion")
    expect(MetricsFormatter.cpuPercent(Double.greatestFiniteMagnitude) == "—", "huge finite CPU values are unavailable")
}

func testChartTimeRangeLabelsFollowLocalClockAndCrossDays() {
    let zone = TimeZone(identifier: "UTC")!
    let base = Date(timeIntervalSince1970: 1_764_000_000) // 2025-11-24 16:00 UTC
    let sameDay = MetricsFormatter.chartTimeRange(start: base, end: base.addingTimeInterval(900), timeZone: zone)
    expect(sameDay?.start == "16:00" && sameDay?.end == "16:15",
           "same-day chart labels show clock times only")
    let crossing = MetricsFormatter.chartTimeRange(
        start: base.addingTimeInterval(28_200),  // 23:50 same evening
        end: base.addingTimeInterval(29_100),    // 00:05 next day
        timeZone: zone
    )
    expect(crossing?.start == "11/24 23:50" && crossing?.end == "11/25 00:05",
           "labels crossing midnight carry the date")
    expect(MetricsFormatter.chartTimeRange(start: base.addingTimeInterval(10), end: base, timeZone: zone) == nil,
           "an inverted range produces no labels")
}

func runMetricsFormatterTests() {
    testPercentFormattingRejectsInvalidValues()
    testFormatsMetricUnitsAndUnavailableValues()
    testFormatsMemoryUsedAndTotalTogether()
    testFormatsCoverageDurationAndDoubleByteTotals()
    testChartTimeRangeLabelsFollowLocalClockAndCrossDays()
}
