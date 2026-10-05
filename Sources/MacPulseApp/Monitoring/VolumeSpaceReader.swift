import Foundation

struct VolumeSpace: Sendable, Equatable, Identifiable {
    /// Mounted path: stable and unique even when two volumes share a name.
    let id: String
    let name: String
    let totalBytes: UInt64
    let availableBytes: UInt64

    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
}

enum VolumeSpaceReader {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsReadOnlyKey
    ]

    static func read() -> [VolumeSpace] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity,
                  total > 0,
                  let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
            // Read-only system snapshots report zero available space and would
            // only read as a broken entry; capacity matters for writable volumes.
            guard values.volumeIsReadOnly != true else { return nil }
            return VolumeSpace(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                totalBytes: UInt64(max(total, 0)),
                availableBytes: UInt64(max(available, 0))
            )
        }
    }
}
