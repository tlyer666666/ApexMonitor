import Foundation

public struct HistoryFileStore: Sendable {
    public let directory: URL
    public let fileName: String

    public init(directory: URL, fileName: String = "history-v1.json") {
        self.directory = directory
        self.fileName = fileName
    }

    public var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    public static func defaultStore() -> HistoryFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return HistoryFileStore(directory: base.appendingPathComponent("MacPulse", isDirectory: true))
    }

    public func read() throws -> [MinuteBucket] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard (attributes[.size] as? NSNumber)?.int64Value ?? 0 <= 64 * 1_024 * 1_024 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let buckets = try decoder.decode([MinuteBucket].self, from: data)
        guard buckets.count <= 100_000, buckets.allSatisfy(\.isValidHistory) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return buckets
    }

    public func load() -> [MinuteBucket] {
        (try? read()) ?? []
    }

    @discardableResult
    public func save(_ buckets: [MinuteBucket]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(buckets)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
