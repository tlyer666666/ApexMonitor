import Foundation

public enum MetricsFormatter {
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    public static func cpuPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    public static func memorySummary(usedBytes: UInt64?, totalBytes: UInt64?) -> String {
        guard let usedBytes, let totalBytes else { return "物理内存" }
        return "\(bytes(usedBytes)) / \(bytes(totalBytes))"
    }

    public static func bytesPerSecond(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value < 1_024 { return String(format: "%.0f B/s", value) }
        let units = ["KB/s", "MB/s", "GB/s", "TB/s"]
        var scaled = value / 1_024
        var unit = 0
        while scaled >= 1_024 && unit < units.count - 1 {
            scaled /= 1_024
            unit += 1
        }
        return String(format: "%.1f %@", scaled, units[unit])
    }
}
