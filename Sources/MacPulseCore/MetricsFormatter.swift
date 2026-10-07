import Foundation

public enum MetricsFormatter {
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0,
              let rounded = Int(exactly: value.rounded()) else { return "—" }
        return "\(rounded)%"
    }

    public static func cpuPercent(_ value: Double?) -> String {
        percent(value)
    }

    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    public static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        // Clamp to 2^62 (exact in Double) so absurd counter reads can never
        // trap the Int64 conversion; ByteCountFormatter caps far below this.
        let bounded = min(value.rounded(), 4_611_686_018_427_387_904)
        return ByteCountFormatter.string(fromByteCount: Int64(bounded), countStyle: .binary)
    }

    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return L10n.Formatter.unavailable }
        if seconds < 60 { return "\(Int(seconds.rounded())) \(L10n.Formatter.seconds)" }
        if seconds < 3_600 { return "\(Int((seconds / 60).rounded())) \(L10n.Formatter.minutes)" }
        return String(format: "%.1f \(L10n.Formatter.hours)", seconds / 3_600)
    }

    public static func memorySummary(usedBytes: UInt64?, totalBytes: UInt64?) -> String {
        guard let usedBytes, let totalBytes else { return L10n.Formatter.memoryFallback }
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
