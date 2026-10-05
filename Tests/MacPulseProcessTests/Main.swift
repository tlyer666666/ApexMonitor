import Darwin
import Foundation

private struct ReferenceProcess {
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let cpuNanoseconds: UInt64

    func hasSameIdentity(as other: ReferenceProcess) -> Bool {
        startSeconds == other.startSeconds && startMicroseconds == other.startMicroseconds
    }
}

private enum ProcessTestError: Error {
    case enumerationFailed
    case invalidByteCapacity
    case invalidResultCount
}

/// Independent oracle: pass the raw storage's byte count, not its PID count.
private func referencePIDs() throws -> [pid_t] {
    // Mirror the production retry: a size-estimate race surfaces as -1.
    for _ in 0..<3 {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { throw ProcessTestError.enumerationFailed }
        var capacity = Int(estimate) + 1
        let maximumCapacity = Int(Int32.max) / MemoryLayout<pid_t>.stride
        var estimateRaced = false
        enumeration: while capacity <= maximumCapacity {
            var pids = [pid_t](repeating: 0, count: capacity)
            let actual = try pids.withUnsafeMutableBytes { bytes -> Int32 in
                guard let byteCount = Int32(exactly: bytes.count) else {
                    throw ProcessTestError.invalidByteCapacity
                }
                return proc_listallpids(bytes.baseAddress, byteCount)
            }
            if actual < 0 {
                estimateRaced = true
                break enumeration
            }
            guard actual > 0 else { throw ProcessTestError.enumerationFailed }
            guard Int(actual) <= capacity else { throw ProcessTestError.invalidResultCount }
            if Int(actual) < capacity {
                print("Reference enumeration: byteCapacity=\(capacity * MemoryLayout<pid_t>.stride), pidStride=\(MemoryLayout<pid_t>.stride), returnedPIDs=\(actual)")
                return Array(pids.prefix(Int(actual)).filter { $0 > 0 })
            }
            guard capacity <= maximumCapacity / 2 else { break }
            capacity *= 2
        }
        guard estimateRaced else { break }
    }
    throw ProcessTestError.invalidByteCapacity
}

private func referenceSameUserProcesses() throws -> [pid_t: ReferenceProcess] {
    var result: [pid_t: ReferenceProcess] = [:]
    let size = Int32(MemoryLayout<proc_taskallinfo>.size)
    for pid in try referencePIDs() {
        var info = proc_taskallinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size,
              info.pbsd.pbi_uid == geteuid() else { continue }
        let cpu = info.ptinfo.pti_total_user.addingReportingOverflow(info.ptinfo.pti_total_system)
        guard !cpu.overflow else { continue }
        result[pid] = ReferenceProcess(
            startSeconds: info.pbsd.pbi_start_tvsec,
            startMicroseconds: info.pbsd.pbi_start_tvusec,
            cpuNanoseconds: cpu.partialValue
        )
    }
    return result
}

@main
private struct ProcessTests {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--core" {
            runProcessTableTests()
            finishTests()
        }
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("PASS: \(message)")
            } else {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        do {
            let before = try referenceSameUserProcesses()
            let samples = ProcessSampler().read()
            let sampleTime = ProcessInfo.processInfo.systemUptime
            let after = try referenceSameUserProcesses()
            // Only compare identities readable before AND after sampling. This
            // excludes normal exits and PID reuse without a fixed process count.
            let stable = before.filter { pid, process in
                after[pid].map { process.hasSameIdentity(as: $0) } ?? false
            }
            let sampledPIDs = Set(samples.map(\.pid))
            let stablePIDs = Set(stable.keys)
            let observedStable = stablePIDs.intersection(sampledPIDs)
            let missing = stablePIDs.subtracting(sampledPIDs)
            print("Permission-scoped counts: sameUserBefore=\(before.count), sameUserAfter=\(after.count), stableReadable=\(stable.count), sampledStable=\(observedStable.count), sampledReadable=\(samples.count), missing=\(missing.count)")
            check(stable[getpid()] != nil, "reference includes this same-user readable test process")
            check(missing.isEmpty, "sampling includes every stable same-user readable reference PID")
            check(sampledPIDs.count == samples.count, "process samples contain no duplicate PIDs")
            check(sampledPIDs.contains(getpid()), "sampling includes the test process itself")

            let comparable = samples.filter { stable[$0.pid] != nil }
            check(samples.allSatisfy { $0.startIdentity != nil }, "production sampling supplies a start identity for every readable process")
            check(comparable.allSatisfy { sample in
                guard let reference = stable[sample.pid], let identity = sample.startIdentity else { return false }
                return identity.seconds == reference.startSeconds
                    && identity.microseconds == reference.startMicroseconds
            }, "sample start identity matches both TASKALLINFO seconds and microseconds")
            check(!comparable.isEmpty, "CPU unit checks have real comparable samples")
            check(comparable.allSatisfy { sample in
                guard let old = stable[sample.pid], let new = after[sample.pid] else { return false }
                return old.cpuNanoseconds <= sample.cpuTimeNanoseconds
                    && sample.cpuTimeNanoseconds <= new.cpuNanoseconds
            }, "sample CPU nanoseconds lie between independent TASKALLINFO counter reads")

            var table = ProcessTable()
            let first = table.update(samples, at: sampleTime)
            check(first.processCount == samples.count, "process count describes only the readable sample")
            check(first.topByCPU.count == min(samples.count, ProcessTable.topLimit)
                  && first.topByMemory.count == min(samples.count, ProcessTable.topLimit),
                  "Top10 is bounded within the readable sample, not all system processes")
            check(first.topByCPU.allSatisfy { $0.cpuPercent == nil }, "first live sample establishes CPU baselines")
            let next = ProcessSampler().read()
            let nextTime = ProcessInfo.processInfo.systemUptime
            check(nextTime > sampleTime, "live sampling uses increasing system uptime seconds")
            let second = table.update(next, at: nextTime)
            check(second.topByCPU.allSatisfy { $0.cpuPercent.map { $0.isFinite && $0 >= 0 } ?? true },
                  "live CPU deltas are finite and nonnegative when available")
        } catch {
            failures += 1
            fputs("FAIL: independent process verification failed: \(error)\n", stderr)
        }
        if failures > 0 {
            fputs("\(failures) process test(s) failed.\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("All process sampling tests passed.")
    }
}
