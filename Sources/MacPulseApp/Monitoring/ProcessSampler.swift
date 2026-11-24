import Darwin
import Foundation

struct LoadAverage: Sendable, Equatable {
    let one: Double
    let five: Double
    let fifteen: Double
}

enum SystemDetailReader {
    static func loadAverage() -> LoadAverage? {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) == 3 else { return nil }
        return LoadAverage(one: values[0], five: values[1], fifteen: values[2])
    }
}

/// Samples processes readable through libproc under the caller's permissions.
/// Denied/exited processes are skipped; this is not a census of all processes.
final class ProcessSampler {
    private static let timebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom > 0 else {
            return (1, 1)
        }
        return (info.numer, info.denom)
    }()

    /// Converts Mach absolute time ticks to nanoseconds using overflow-safe
    /// integer arithmetic: `(ticks / denom) * numer + ((ticks % denom) * numer) / denom`.
    static func machTicksToNanoseconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> UInt64? {
        guard denom > 0 else { return nil }
        let n = UInt64(numer)
        let d = UInt64(denom)
        let quotient = ticks / d
        let remainder = ticks % d
        let scaledQuotient = quotient.multipliedReportingOverflow(by: n)
        guard !scaledQuotient.overflow else { return nil }
        // `remainder < d <= UInt32.max` and `n <= UInt32.max`, so `remainder * n` cannot overflow UInt64.
        let scaledRemainder = (remainder * n) / d
        let total = scaledQuotient.partialValue.addingReportingOverflow(scaledRemainder)
        guard !total.overflow else { return nil }
        return total.partialValue
    }

    func read() -> [RawProcessSample] {
        let pids = Self.readPIDs()
        var samples: [RawProcessSample] = []
        samples.reserveCapacity(pids.count)
        let taskInfoSize = Int32(MemoryLayout<proc_taskallinfo>.size)
        let (numer, denom) = Self.timebase
        for pid in pids where pid > 0 {
            var info = proc_taskallinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, taskInfoSize) == taskInfoSize else { continue }
            let cpuTicks = info.ptinfo.pti_total_user.addingReportingOverflow(info.ptinfo.pti_total_system)
            guard !cpuTicks.overflow,
                  let cpuNanoseconds = Self.machTicksToNanoseconds(cpuTicks.partialValue, numer: numer, denom: denom) else {
                continue
            }
            // Name, birth time, and counters come from the same task-info read.
            let name = Self.name(&info.pbsd.pbi_name) ?? Self.name(&info.pbsd.pbi_comm)
            samples.append(RawProcessSample(
                pid: pid,
                name: name,
                residentBytes: info.ptinfo.pti_resident_size,
                cpuTimeNanoseconds: cpuNanoseconds,
                startIdentity: ProcessStartIdentity(
                    seconds: info.pbsd.pbi_start_tvsec,
                    microseconds: info.pbsd.pbi_start_tvusec
                )
            ))
        }
        return samples
    }

    private static func readPIDs() -> [pid_t] {
        // The size estimate can race with process creation: libproc returns -1
        // when the buffer is already too small. Re-estimate a few times before
        // giving up; a genuinely shrinking system is not a real case.
        for _ in 0..<3 {
            let declared = proc_listallpids(nil, 0)
            guard declared > 0 else { return [] }
            var capacity = Int(declared) + 1
            let maximumCapacity = Int(Int32.max) / MemoryLayout<pid_t>.stride
            var estimateRaced = false
            while capacity <= maximumCapacity {
                var pids = [pid_t](repeating: 0, count: capacity)
                // libproc accepts byte capacity but returns the number of PIDs.
                let byteCapacity = Int32(capacity * MemoryLayout<pid_t>.stride)
                let actual = pids.withUnsafeMutableBufferPointer { buffer in
                    proc_listallpids(buffer.baseAddress, byteCapacity)
                }
                if actual < 0 {
                    estimateRaced = true
                    break
                }
                guard actual > 0, Int(actual) <= capacity else { return [] }
                if Int(actual) < capacity {
                    return Array(pids.prefix(Int(actual)))
                }
                // Processes may appear between the size query and the actual read.
                guard capacity <= maximumCapacity / 2 else { return [] }
                capacity *= 2
            }
            guard estimateRaced else { break }
        }
        return []
    }

    private static func name<T>(_ field: inout T) -> String? {
        withUnsafeBytes(of: &field) { bytes in
            let prefix = bytes.prefix { $0 != 0 }
            return prefix.isEmpty ? nil : String(decoding: prefix, as: UTF8.self)
        }
    }
}
