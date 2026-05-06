import Foundation

private let maxCorruptChunksBeforeBan = 3
private let corruptWindowSeconds: TimeInterval = 300

public struct CorruptChunkRecord: Equatable, Sendable {
    public let fileHash: Data
    public let offset: UInt64
    public let length: UInt64
    public let sourceID: KadUInt128
    public let timestamp: Date

    public init(
        fileHash: Data,
        offset: UInt64,
        length: UInt64,
        sourceID: KadUInt128,
        timestamp: Date = Date()
    ) {
        self.fileHash = fileHash
        self.offset = offset
        self.length = length
        self.sourceID = sourceID
        self.timestamp = timestamp
    }
}

/// Corruption black box: records corrupt chunks and detects malicious sources.
public final class CoreCorruptionBlackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CorruptChunkRecord] = []

    public init() {}

    /// Records a corrupt chunk associated with a source.
    public func recordCorruptChunk(fileHash: Data, offset: UInt64, length: UInt64, sourceID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }

        let record = CorruptChunkRecord(
            fileHash: fileHash,
            offset: offset,
            length: length,
            sourceID: sourceID
        )
        records.append(record)
    }

    /// A source is "bad" if it has more than 3 corrupt chunks in the last 5 minutes.
    public func isSourceBad(sourceID: KadUInt128) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = Date().addingTimeInterval(-corruptWindowSeconds)
        let recent = records.filter { $0.sourceID == sourceID && $0.timestamp >= cutoff }
        return recent.count > maxCorruptChunksBeforeBan
    }

    /// Returns the list of corrupt ranges for a file.
    public func corruptChunks(for fileHash: Data) -> [(offset: UInt64, length: UInt64)] {
        lock.lock()
        defer { lock.unlock() }

        return records
            .filter { $0.fileHash == fileHash }
            .map { (offset: $0.offset, length: $0.length) }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        records.removeAll()
    }
}
