import Foundation
#if canImport(MacPulseCore)
import MacPulseCore
#endif

func testFormatsMetricUnitsAndUnavailableValues() {
    expect(MetricsFormatter.cpuPercent(12.6) == "13%", "CPU percentage rounds to an integer")
    expect(MetricsFormatter.bytes(1_610_612_736) == "1.5 GB", "memory uses binary units with one decimal place")
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

func runMetricsFormatterTests() {
    testFormatsMetricUnitsAndUnavailableValues()
    testFormatsMemoryUsedAndTotalTogether()
}
