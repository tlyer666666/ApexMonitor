import Foundation

private func fixture(_ time: Date, _ cpu: Double) -> MinuteBucket {
    MinuteBucket(minuteStart: time, sampleCount: 1, cpuAverage: cpu, cpuPeak: cpu,
                 memoryAverage: nil, memoryPeak: nil, diskReadAverage: nil, diskReadPeak: nil,
                 diskWriteAverage: nil, diskWritePeak: nil, networkReceiveAverage: nil,
                 networkReceivePeak: nil, networkSendAverage: nil, networkSendPeak: nil)
}

@main
struct RepositoryTests {
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-repository-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = HistoryFileStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_700_006_520)
        let old = fixture(now.addingTimeInterval(-120), 20)
        let new = fixture(now.addingTimeInterval(-60), 40)
        precondition(file.save([old]))
        let repository = HistoryRepository(file: file)
        repository.load { _ in }
        let saved = repository.saveAndWait(session: [new], now: now)
        guard saved.error == nil, file.load().count == 2 else {
            fputs("FAIL: fast quit must preserve disk history before async load publication\n", stderr)
            exit(1)
        }
        print("PASS: fast quit preserves disk history before publication")
        repository.save(session: [], now: now) { _ in }
        _ = repository.saveAndWait(session: [new], now: now)
        guard file.load() == HistoryAnalyzer.mergedBuckets([old, new]) else {
            fputs("FAIL: final save must win over queued boundary saves without duplicating minutes\n", stderr)
            exit(1)
        }
        print("PASS: final save wins over old queued snapshots, without double merging")
        let duplicate = repository.saveAndWait(session: [new], now: now)
        guard duplicate.buckets == saved.buckets else { exit(1) }
        print("PASS: repeated saves do not increase sample counts")
        let rollback = repository.saveAndWait(session: [new], now: now.addingTimeInterval(-180))
        guard rollback.buckets.count == 2, file.load().count == 2 else {
            fputs("FAIL: saving after wall-clock rollback deleted valid future-dated history\n", stderr)
            exit(1)
        }
        print("PASS: saving after clock rollback preserves already recorded history")

        let corruptDirectory = directory.appendingPathComponent("corrupt")
        try! FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corrupt = HistoryFileStore(directory: corruptDirectory)
        let original = Data("user history could not be decoded".utf8)
        try! original.write(to: corrupt.fileURL)
        let recovering = HistoryRepository(file: corrupt)
        let failed = recovering.saveAndWait(session: [new], now: now)
        guard failed.error != nil, (try? Data(contentsOf: corrupt.fileURL)) == original else { exit(1) }
        print("PASS: unreadable existing history is reported and never overwritten")

        let blocked = directory.appendingPathComponent("not-a-directory")
        try! Data("sentinel".utf8).write(to: blocked)
        let unavailable = HistoryRepository(file: HistoryFileStore(directory: blocked))
        guard unavailable.saveAndWait(session: [new], now: now).error != nil else { exit(1) }
        print("PASS: write failure is surfaced to the caller")

        let invalidDirectory = directory.appendingPathComponent("invalid-values")
        let invalidFile = HistoryFileStore(directory: invalidDirectory)
        precondition(invalidFile.save([old]))
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: invalidFile.fileURL)) as! [[String: Any]]
        json[0]["sampleCount"] = -1
        let invalidData = try! JSONSerialization.data(withJSONObject: json)
        try! invalidData.write(to: invalidFile.fileURL)
        let invalidStore = HistoryRepository(file: invalidFile)
        let invalidResult = invalidStore.saveAndWait(session: [new], now: now)
        guard invalidResult.error != nil, (try? Data(contentsOf: invalidFile.fileURL)) == invalidData else {
            fputs("FAIL: semantically invalid history must be preserved and reported, not merged\n", stderr)
            exit(1)
        }
        print("PASS: invalid numeric history is preserved rather than merged into live data")
    }
}
