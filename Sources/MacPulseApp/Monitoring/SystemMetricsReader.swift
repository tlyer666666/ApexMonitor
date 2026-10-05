import Darwin
import Foundation
import IOKit
import IOKit.storage

struct InterfaceDetail: Sendable, Equatable, Identifiable {
    let name: String
    let isUp: Bool
    let isRunning: Bool
    let ipv4: [String]
    let ipv6: [String]

    var id: String { name }
    var isConnected: Bool { isUp && isRunning }
}

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
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        let result = host_processor_info(
            host,
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
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS,
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

    func readInterfaceDetails() -> [InterfaceDetail] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        struct Draft {
            var up = false
            var running = false
            var ipv4: [String] = []
            var ipv6: [String] = []
        }

        var drafts: [String: Draft] = [:]
        var order: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let namePointer = entry.ifa_name, let address = entry.ifa_addr else { continue }
            let name = String(cString: namePointer)
            if drafts[name] == nil {
                order.append(name)
                drafts[name] = Draft()
            }

            switch address.pointee.sa_family {
            case UInt8(AF_LINK):
                drafts[name]?.up = entry.ifa_flags & UInt32(IFF_UP) != 0
                drafts[name]?.running = entry.ifa_flags & UInt32(IFF_RUNNING) != 0
            case UInt8(AF_INET):
                if let text = Self.addressString(address) {
                    drafts[name]?.ipv4.append(text)
                }
            case UInt8(AF_INET6):
                if let text = Self.addressString(address) {
                    drafts[name]?.ipv6.append(text)
                }
            default:
                break
            }
        }

        return order.compactMap { name in
            guard let draft = drafts[name] else { return nil }
            return InterfaceDetail(
                name: name,
                isUp: draft.up,
                isRunning: draft.running,
                ipv4: draft.ipv4,
                ipv6: draft.ipv6
            )
        }
    }

    private static func addressString(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = host.withUnsafeMutableBufferPointer { buffer in
            getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                buffer.baseAddress,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
        }
        guard status == 0 else { return nil }
        return String(cString: host)
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
