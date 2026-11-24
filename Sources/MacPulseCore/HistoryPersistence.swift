import Darwin
import Foundation

public struct HistoryFileStore: Sendable {
    private static let maxFileSizeBytes = 64 * 1_024 * 1_024
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
        let fd = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 {
            let err = errno
            if err == ENOENT { return [] }
            if err == ELOOP { throw CocoaError(.fileReadNoPermission) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
        }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard st.st_size >= 0, st.st_size <= Int64(Self.maxFileSizeBytes) else {
            throw CocoaError(.fileReadTooLarge)
        }

        var data = Data()
        if st.st_size > 0 {
            data.reserveCapacity(Int(st.st_size))
        }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            if bytesRead == 0 { break }
            if data.count + bytesRead > Self.maxFileSizeBytes {
                throw CocoaError(.fileReadTooLarge)
            }
            data.append(buffer, count: bytesRead)
        }

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
        // The writer must uphold the same contract the reader enforces, so a
        // successful save can never produce a file this app cannot reopen.
        guard buckets.count <= 100_000, buckets.allSatisfy(\.isValidHistory) else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(buckets)
            guard data.count <= 64 * 1_024 * 1_024 else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
