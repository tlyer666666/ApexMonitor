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

    public func load() -> [MinuteBucket] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let buckets = try? decoder.decode([MinuteBucket].self, from: data) else { return [] }
        return buckets
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
