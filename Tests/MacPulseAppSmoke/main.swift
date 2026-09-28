import Foundation

let reader = SystemMetricsReader()
let networkInterfaces = reader.readNetworkInterfaces()
var networkAccumulator = NetworkCounterAccumulator()
let networkTotals = networkInterfaces.flatMap { networkAccumulator.update($0) }
let sample = reader.read(networkCounters: networkTotals)
let memoryIsValid = sample.memoryUsedBytes.map { $0 > 0 } == true
    && sample.memoryTotalBytes.map { $0 > 0 } == true

print("CPU counters: \(sample.cpu == nil ? "unavailable" : "available")")
print("Memory: \(sample.memoryUsedBytes.map(String.init) ?? "—") / \(sample.memoryTotalBytes.map(String.init) ?? "—") bytes")
print("Disk counters: \(sample.diskReadBytes.map(String.init) ?? "—") read, \(sample.diskWrittenBytes.map(String.init) ?? "—") written")
print("Network interfaces: \(networkInterfaces?.count ?? 0); runtime receive delta: \(networkTotals?.receivedBytes ?? 0), send delta: \(networkTotals?.sentBytes ?? 0)")

guard sample.cpu != nil, memoryIsValid else {
    fputs("Required CPU or memory counters are unavailable.\n", stderr)
    exit(EXIT_FAILURE)
}

guard sample.diskReadBytes != nil, sample.diskWrittenBytes != nil else {
    fputs("Disk IOKit counters are unavailable on this host.\n", stderr)
    exit(EXIT_FAILURE)
}

guard let networkInterfaces, !networkInterfaces.isEmpty, networkTotals != nil else {
    fputs("Network interface counters are unavailable on this host.\n", stderr)
    exit(EXIT_FAILURE)
}

guard networkTotals?.receivedBytes == 0, networkTotals?.sentBytes == 0 else {
    fputs("The first network sample should establish a baseline without reporting historical traffic.\n", stderr)
    exit(EXIT_FAILURE)
}

print("All system counter smoke checks passed.")
