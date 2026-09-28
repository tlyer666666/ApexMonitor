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

/// Enumerates same-user processes via libproc. Root/system processes that
/// refuse PROC_PIDTASKINFO are skipped rather than reported as zero usage.
final class ProcessSampler {
    func read() -> [RawProcessSample] {
        let declared = proc_listallpids(nil, 0)
        guard declared > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(declared) + 1)
        let actual = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard actual > 0 else { return [] }

        var samples: [RawProcessSample] = []
        samples.reserveCapacity(Int(actual))
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        for pid in pids.prefix(Int(actual)) where pid > 0 {
            var taskInfo = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize) == taskInfoSize else { continue }
            samples.append(RawProcessSample(
                pid: pid,
                name: Self.name(of: pid),
                residentBytes: taskInfo.pti_resident_size,
                cpuTimeNanoseconds: taskInfo.pti_total_user &+ taskInfo.pti_total_system
            ))
        }
        return samples
    }

    private static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
