import Darwin
import Foundation
import IOKit
import IOKit.storage

struct SystemMetricsReader {
    func read(networkCounters: NetworkCounterTotals? = nil) -> RawMetricsSample {
        let memory = readMemory()
        let disk = readDiskCounters()

        return RawMetricsSample(
            uptime: ProcessInfo.processInfo.systemUptime,
            cpu: readProcessorTicks(),
            memoryUsedBytes: memory?.used,
            memoryTotalBytes: memory?.total,
            diskReadBytes: disk?.read,
            diskWrittenBytes: disk?.written,
            networkReceivedBytes: networkCounters?.receivedBytes,
            networkSentBytes: networkCounters?.sentBytes
        )
    }

    private func readProcessorTicks() -> ProcessorTicks? {
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            _ = vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), byteCount)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        let stateCount = Int(CPU_STATE_MAX)
        for processor in 0..<Int(processorCount) {
            let base = processor * stateCount
            user &+= MetricCounter.unsignedValue(fromSigned32: Int32(info[base + Int(CPU_STATE_USER)]))
            system &+= MetricCounter.unsignedValue(fromSigned32: Int32(info[base + Int(CPU_STATE_SYSTEM)]))
            idle &+= MetricCounter.unsignedValue(fromSigned32: Int32(info[base + Int(CPU_STATE_IDLE)]))
            nice &+= MetricCounter.unsignedValue(fromSigned32: Int32(info[base + Int(CPU_STATE_NICE)]))
        }
        return ProcessorTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private func readMemory() -> (used: UInt64, total: UInt64)? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS,
              pageSize > 0 else { return nil }

        let usedPages = UInt64(statistics.active_count)
            &+ UInt64(statistics.wire_count)
            &+ UInt64(statistics.compressor_page_count)
        return (usedPages &* UInt64(pageSize), ProcessInfo.processInfo.physicalMemory)
    }

    private func readDiskCounters() -> (read: UInt64, written: UInt64)? {
        guard let matching = IOServiceMatching(kIOBlockStorageDriverClass) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var readTotal: UInt64 = 0
        var writtenTotal: UInt64 = 0
        var foundStatistics = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let property = IORegistryEntryCreateCFProperty(
                service,
                kIOBlockStorageDriverStatisticsKey as CFString,
                kCFAllocatorDefault,
                0
            ) {
                let value = property.takeRetainedValue()
                if let statistics = value as? NSDictionary,
                   let read = statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber,
                   let written = statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber {
                    readTotal &+= read.uint64Value
                    writtenTotal &+= written.uint64Value
                    foundStatistics = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return foundStatistics ? (readTotal, writtenTotal) : nil
    }

    func readNetworkInterfaces() -> [String: NetworkInterfaceCounters]? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }

        var interfaces: [String: NetworkInterfaceCounters] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current?.pointee {
            if let namePointer = entry.ifa_name,
               let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let rawData = entry.ifa_data {
                let name = String(cString: namePointer)
                if interfaces[name] == nil {
                    let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                    interfaces[name] = NetworkInterfaceCounters(
                        receivedBytes: UInt64(data.ifi_ibytes),
                        sentBytes: UInt64(data.ifi_obytes)
                    )
                }
            }
            current = entry.ifa_next
        }
        return interfaces.isEmpty ? nil : interfaces
    }
}
