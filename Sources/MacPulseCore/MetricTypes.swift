import Foundation

public struct ProcessorTicks: Sendable, Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct RawMetricsSample: Sendable, Equatable {
    public let uptime: Double
    public let cpu: ProcessorTicks?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let diskReadBytes: UInt64?
    public let diskWrittenBytes: UInt64?
    public let networkReceivedBytes: UInt64?
    public let networkSentBytes: UInt64?

    public init(
        uptime: Double,
        cpu: ProcessorTicks?,
        memoryUsedBytes: UInt64?,
        memoryTotalBytes: UInt64?,
        diskReadBytes: UInt64?,
        diskWrittenBytes: UInt64?,
        networkReceivedBytes: UInt64?,
        networkSentBytes: UInt64?
    ) {
        self.uptime = uptime
        self.cpu = cpu
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskReadBytes = diskReadBytes
        self.diskWrittenBytes = diskWrittenBytes
        self.networkReceivedBytes = networkReceivedBytes
        self.networkSentBytes = networkSentBytes
    }
}

public struct MetricsSnapshot: Sendable, Equatable {
    public let timestamp: Double
    public let cpuPercent: Double?
    public let cpuUserPercent: Double?
    public let cpuSystemPercent: Double?
    public let cpuNicePercent: Double?
    public let cpuIdlePercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let memoryPercent: Double?
    public let diskReadBytesPerSecond: Double?
    public let diskWriteBytesPerSecond: Double?
    public let networkReceiveBytesPerSecond: Double?
    public let networkSendBytesPerSecond: Double?

    public init(
        timestamp: Double,
        cpuPercent: Double?,
        cpuUserPercent: Double? = nil,
        cpuSystemPercent: Double? = nil,
        cpuNicePercent: Double? = nil,
        cpuIdlePercent: Double? = nil,
        memoryUsedBytes: UInt64?,
        memoryTotalBytes: UInt64?,
        memoryPercent: Double?,
        diskReadBytesPerSecond: Double?,
        diskWriteBytesPerSecond: Double?,
        networkReceiveBytesPerSecond: Double?,
        networkSendBytesPerSecond: Double?
    ) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.cpuUserPercent = cpuUserPercent
        self.cpuSystemPercent = cpuSystemPercent
        self.cpuNicePercent = cpuNicePercent
        self.cpuIdlePercent = cpuIdlePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPercent = memoryPercent
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.networkReceiveBytesPerSecond = networkReceiveBytesPerSecond
        self.networkSendBytesPerSecond = networkSendBytesPerSecond
    }
}
