import Foundation

public enum CoreTransferStoreError: Error, Equatable, LocalizedError {
    case transferNotFound(UUID)
    case blockOutOfBounds(offset: UInt64, length: UInt64, fileSize: UInt64)
    case hashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .transferNotFound(let id):
            return "Transfer metadata not found: \(id.uuidString)."
        case .blockOutOfBounds(let offset, let length, let fileSize):
            return "Block out of bounds: offset \(offset), length \(length), file size \(fileSize)."
        case .hashMismatch(let expected, let actual):
            return "Transfer hash mismatch: expected \(expected), actual \(actual)."
        }
    }
}

public enum CoreChunkStatus: String, Codable, Equatable, Sendable {
    case missing
    case partial
    case complete
}

public struct CoreByteRange: Codable, Equatable, Sendable {
    public var offset: UInt64
    public var length: UInt64

    public var endOffset: UInt64 {
        offset + length
    }

    public init(offset: UInt64, length: UInt64) {
        self.offset = offset
        self.length = length
    }
}

private struct CoreServerBootstrapState: Codable {
    var version: Int
}

public struct CoreChunk: Codable, Equatable, Sendable {
    public var index: Int
    public var offset: UInt64
    public var length: UInt64
    public var completedBytes: UInt64

    public var status: CoreChunkStatus {
        if completedBytes == 0 {
            return .missing
        }

        return completedBytes >= length ? .complete : .partial
    }

    public init(index: Int, offset: UInt64, length: UInt64, completedBytes: UInt64) {
        self.index = index
        self.offset = offset
        self.length = length
        self.completedBytes = completedBytes
    }
}

public struct CoreChunkMap: Codable, Equatable, Sendable {
    public static let ed2kChunkSize: UInt64 = 9_728_000

    public var fileSizeInBytes: UInt64
    public var chunkSizeInBytes: UInt64
    public private(set) var writtenRanges: [CoreByteRange]

    public var completedBytes: UInt64 {
        writtenRanges.reduce(0) { $0 + $1.length }
    }

    public var chunks: [CoreChunk] {
        guard fileSizeInBytes > 0 else {
            return []
        }

        var output: [CoreChunk] = []
        var offset: UInt64 = 0
        var index = 0

        while offset < fileSizeInBytes {
            let length = min(chunkSizeInBytes, fileSizeInBytes - offset)
            output.append(
                CoreChunk(
                    index: index,
                    offset: offset,
                    length: length,
                    completedBytes: coveredBytes(offset: offset, length: length)
                )
            )
            offset += length
            index += 1
        }

        return output
    }

    public init(
        fileSizeInBytes: UInt64,
        chunkSizeInBytes: UInt64 = Self.ed2kChunkSize,
        writtenRanges: [CoreByteRange] = []
    ) {
        self.fileSizeInBytes = fileSizeInBytes
        self.chunkSizeInBytes = chunkSizeInBytes
        self.writtenRanges = Self.normalized(writtenRanges)
    }

    public mutating func markWritten(offset: UInt64, length: UInt64) {
        guard length > 0 else {
            return
        }

        writtenRanges.append(CoreByteRange(offset: offset, length: length))
        writtenRanges = Self.normalized(writtenRanges)
    }

    public mutating func clearWritten(offset: UInt64, length: UInt64) {
        guard length > 0 else { return }
        let eraseEnd = offset + length
        writtenRanges = writtenRanges.compactMap { range -> CoreByteRange? in
            let rangeEnd = range.offset + range.length
            if rangeEnd <= offset || range.offset >= eraseEnd {
                return range
            }
            let trimmedStart = max(range.offset, offset)
            let trimmedEnd = min(rangeEnd, eraseEnd)
            if trimmedEnd <= trimmedStart {
                return range
            }
            let beforeLength = trimmedStart - range.offset
            let afterStart = trimmedEnd
            let afterLength = rangeEnd - afterStart
            var result: CoreByteRange?
            if beforeLength > 0 {
                result = CoreByteRange(offset: range.offset, length: beforeLength)
            }
            if afterLength > 0 {
                let after = CoreByteRange(offset: afterStart, length: afterLength)
                if result != nil {
                    writtenRanges.append(after)
                } else {
                    result = after
                }
            }
            return result
        }
        writtenRanges = Self.normalized(writtenRanges)
    }

    private func coveredBytes(offset: UInt64, length: UInt64) -> UInt64 {
        let endOffset = offset + length

        return writtenRanges.reduce(UInt64(0)) { total, range in
            let overlapStart = max(offset, range.offset)
            let overlapEnd = min(endOffset, range.endOffset)

            guard overlapEnd > overlapStart else {
                return total
            }

            return total + (overlapEnd - overlapStart)
        }
    }

    private static func normalized(_ ranges: [CoreByteRange]) -> [CoreByteRange] {
        let sortedRanges = ranges
            .filter { $0.length > 0 }
            .sorted { $0.offset < $1.offset }

        return sortedRanges.reduce(into: []) { output, range in
            guard var lastRange = output.popLast() else {
                output.append(range)
                return
            }

            if range.offset <= lastRange.endOffset {
                let endOffset = max(lastRange.endOffset, range.endOffset)
                lastRange.length = endOffset - lastRange.offset
                output.append(lastRange)
            } else {
                output.append(lastRange)
                output.append(range)
            }
        }
    }
}

public struct CoreTransferRecord: Codable, Equatable, Sendable {
    public var transfer: CoreTransfer
    public var partFileName: String
    public var completedFileName: String?
    public var verifiedHash: String?
    public var verifiedPartHashes: [String?]
    public var peerSourceBookmarks: [CorePeerSourceBookmark]
    public var peerInflightBookmarks: [CorePeerInflightBookmark]
    public var peerChunkRetryBookmarks: [CorePeerChunkRetryBookmark]
    public var chunkMap: CoreChunkMap
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        transfer: CoreTransfer,
        partFileName: String,
        completedFileName: String? = nil,
        verifiedHash: String? = nil,
        verifiedPartHashes: [String?] = [],
        peerSourceBookmarks: [CorePeerSourceBookmark] = [],
        peerInflightBookmarks: [CorePeerInflightBookmark] = [],
        peerChunkRetryBookmarks: [CorePeerChunkRetryBookmark] = [],
        chunkMap: CoreChunkMap,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.transfer = transfer
        self.partFileName = partFileName
        self.completedFileName = completedFileName
        self.verifiedHash = verifiedHash
        self.verifiedPartHashes = verifiedPartHashes
        self.peerSourceBookmarks = peerSourceBookmarks
        self.peerInflightBookmarks = peerInflightBookmarks
        self.peerChunkRetryBookmarks = peerChunkRetryBookmarks
        self.chunkMap = chunkMap
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case transfer
        case partFileName
        case completedFileName
        case verifiedHash
        case verifiedPartHashes
        case peerSourceBookmarks
        case peerInflightBookmarks
        case peerChunkRetryBookmarks
        case chunkMap
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transfer = try container.decode(CoreTransfer.self, forKey: .transfer)
        partFileName = try container.decode(String.self, forKey: .partFileName)
        completedFileName = try container.decodeIfPresent(String.self, forKey: .completedFileName)
        verifiedHash = try container.decodeIfPresent(String.self, forKey: .verifiedHash)
        verifiedPartHashes = try container.decodeIfPresent([String?].self, forKey: .verifiedPartHashes) ?? []
        peerSourceBookmarks = try container.decodeIfPresent([CorePeerSourceBookmark].self, forKey: .peerSourceBookmarks) ?? []
        peerInflightBookmarks = try container.decodeIfPresent([CorePeerInflightBookmark].self, forKey: .peerInflightBookmarks) ?? []
        peerChunkRetryBookmarks = try container.decodeIfPresent([CorePeerChunkRetryBookmark].self, forKey: .peerChunkRetryBookmarks) ?? []
        chunkMap = try container.decodeIfPresent(CoreChunkMap.self, forKey: .chunkMap)
            ?? CoreChunkMap(fileSizeInBytes: transfer.sizeInBytes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct CorePeerSourceBookmark: Codable, Equatable, Sendable {
    public var endpoint: ED2KPeerEndpoint
    public var failureCount: Int
    public var cooldownUntil: Date?

    public init(
        endpoint: ED2KPeerEndpoint,
        failureCount: Int = 0,
        cooldownUntil: Date? = nil
    ) {
        self.endpoint = endpoint
        self.failureCount = max(0, failureCount)
        self.cooldownUntil = cooldownUntil
    }
}

public struct CorePeerInflightBookmark: Codable, Equatable, Sendable {
    public var endpoint: ED2KPeerEndpoint
    public var startOffset: UInt64
    public var endOffset: UInt64
    public var reservedAt: Date

    public init(
        endpoint: ED2KPeerEndpoint,
        startOffset: UInt64,
        endOffset: UInt64,
        reservedAt: Date
    ) {
        self.endpoint = endpoint
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.reservedAt = reservedAt
    }
}

public struct CorePeerChunkRetryBookmark: Codable, Equatable, Sendable {
    public var startOffset: UInt64
    public var endOffset: UInt64
    public var failureCount: Int
    public var cooldownUntil: Date?
    public var lastFailureAt: Date

    public init(
        startOffset: UInt64,
        endOffset: UInt64,
        failureCount: Int,
        cooldownUntil: Date? = nil,
        lastFailureAt: Date
    ) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.failureCount = max(0, failureCount)
        self.cooldownUntil = cooldownUntil
        self.lastFailureAt = lastFailureAt
    }
}

public struct CoreClientIdentity: Codable, Equatable, Sendable {
    public var userHash: Data

    public init(userHash: Data) {
        self.userHash = userHash
    }
}

public struct CoreResumeServerConfiguration: Codable, Equatable, Sendable {
    public var endpoint: ED2KServerEndpoint
    public var clientID: UInt32
    public var tcpPort: UInt16
    public var nickname: String
    public var protocolVersion: UInt32
    public var flags: UInt32

    public init(
        endpoint: ED2KServerEndpoint,
        clientID: UInt32,
        tcpPort: UInt16,
        nickname: String,
        protocolVersion: UInt32,
        flags: UInt32
    ) {
        self.endpoint = endpoint
        self.clientID = clientID
        self.tcpPort = tcpPort
        self.nickname = nickname
        self.protocolVersion = protocolVersion
        self.flags = flags
    }

    public init(sessionConfiguration: ED2KServerSessionConfiguration) {
        self.init(
            endpoint: sessionConfiguration.endpoint,
            clientID: sessionConfiguration.clientID,
            tcpPort: sessionConfiguration.tcpPort,
            nickname: sessionConfiguration.nickname,
            protocolVersion: sessionConfiguration.protocolVersion,
            flags: sessionConfiguration.flags
        )
    }

    public func sessionConfiguration(userHash: Data) -> ED2KServerSessionConfiguration {
        ED2KServerSessionConfiguration(
            endpoint: endpoint,
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            nickname: nickname,
            protocolVersion: protocolVersion,
            flags: flags
        )
    }
}

public struct CoreResumeCheckpoint: Codable, Equatable, Sendable {
    public var activeTransferIDs: [UUID]
    public var activeSearchQuery: String?
    public var serverConfiguration: CoreResumeServerConfiguration?
    public var updatedAt: Date

    public init(
        activeTransferIDs: [UUID],
        activeSearchQuery: String? = nil,
        serverConfiguration: CoreResumeServerConfiguration? = nil,
        updatedAt: Date = Date()
    ) {
        self.activeTransferIDs = activeTransferIDs
        self.activeSearchQuery = activeSearchQuery
        self.serverConfiguration = serverConfiguration
        self.updatedAt = updatedAt
    }
}

public final class CoreTransferStore {
    public let rootDirectory: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let incomingDirectoryOverride: URL?
    private let tempDirectoryOverride: URL?

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        incomingDirectoryOverride = nil
        tempDirectoryOverride = nil
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public init(
        rootDirectory: URL,
        tempDirectory: URL? = nil,
        incomingDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        incomingDirectoryOverride = incomingDirectory
        tempDirectoryOverride = tempDirectory
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public var tempDirectory: URL {
        tempDirectoryOverride ?? rootDirectory.appendingPathComponent("Temp", isDirectory: true)
    }

    public var incomingDirectory: URL {
        incomingDirectoryOverride ?? rootDirectory.appendingPathComponent("Incoming", isDirectory: true)
    }

    public var serversURL: URL {
        rootDirectory.appendingPathComponent("Servers.json")
    }

    public var identityURL: URL {
        rootDirectory.appendingPathComponent("Identity.json")
    }

    public var resumeCheckpointURL: URL {
        rootDirectory.appendingPathComponent("ResumeCheckpoint.json")
    }

    public var runtimeLockURL: URL {
        rootDirectory.appendingPathComponent("Runtime.lock")
    }

    public var serverBootstrapStateURL: URL {
        rootDirectory.appendingPathComponent("ServerBootstrap.json")
    }

    public func metadataURL(for id: UUID) -> URL {
        tempDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    public func partFileURL(for id: UUID) -> URL {
        tempDirectory.appendingPathComponent("\(id.uuidString).part")
    }

    public func completedFileURL(for record: CoreTransferRecord) -> URL? {
        guard let completedFileName = record.completedFileName else {
            return nil
        }

        return incomingDirectory.appendingPathComponent(completedFileName)
    }

    public func loadRecord(for id: UUID) throws -> CoreTransferRecord {
        let url = metadataURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CoreTransferStoreError.transferNotFound(id)
        }

        return try loadRecord(from: url)
    }

    public func loadSnapshot() throws -> CoreSnapshot {
        try prepareDirectories()

        let urls = try fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil
        )

        let records = try urls
            .filter { $0.pathExtension == "json" }
            .map(loadRecord)
            .sorted { $0.updatedAt > $1.updatedAt }

        return CoreSnapshot(
            transfers: records.map(\.transfer),
            servers: try loadServers()
        )
    }

    public func loadServers() throws -> [CoreServer] {
        try prepareDirectories()

        guard fileManager.fileExists(atPath: serversURL.path) else {
            return []
        }

        let data = try Data(contentsOf: serversURL)
        return try decoder.decode([CoreServer].self, from: data)
    }

    public func saveServers(_ servers: [CoreServer]) throws {
        try prepareDirectories()
        let data = try encoder.encode(servers)
        try data.write(to: serversURL, options: [.atomic])
    }

    public func loadServerBootstrapVersion() throws -> Int {
        try prepareDirectories()

        guard fileManager.fileExists(atPath: serverBootstrapStateURL.path) else {
            return 0
        }

        let data = try Data(contentsOf: serverBootstrapStateURL)
        return try decoder.decode(CoreServerBootstrapState.self, from: data).version
    }

    public func saveServerBootstrapVersion(_ version: Int) throws {
        try prepareDirectories()
        let state = CoreServerBootstrapState(version: version)
        let data = try encoder.encode(state)
        try data.write(to: serverBootstrapStateURL, options: [.atomic])
    }

    public func loadClientIdentity() throws -> CoreClientIdentity? {
        try prepareDirectories()

        guard fileManager.fileExists(atPath: identityURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: identityURL)
        return try decoder.decode(CoreClientIdentity.self, from: data)
    }

    public func saveClientIdentity(_ identity: CoreClientIdentity) throws {
        try prepareDirectories()
        let data = try encoder.encode(identity)
        try data.write(to: identityURL, options: [.atomic])
    }

    public func loadResumeCheckpoint() throws -> CoreResumeCheckpoint? {
        try prepareDirectories()

        guard fileManager.fileExists(atPath: resumeCheckpointURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: resumeCheckpointURL)
        return try decoder.decode(CoreResumeCheckpoint.self, from: data)
    }

    public func saveResumeCheckpoint(_ checkpoint: CoreResumeCheckpoint) throws {
        try prepareDirectories()
        let data = try encoder.encode(checkpoint)
        try data.write(to: resumeCheckpointURL, options: [.atomic])
    }

    public func clearResumeCheckpoint() throws {
        try removeIfPresent(resumeCheckpointURL)
    }

    @discardableResult
    public func activateRuntimeLock() throws -> Bool {
        try prepareDirectories()
        let hadExistingLock = fileManager.fileExists(atPath: runtimeLockURL.path)
        let lockData = try encoder.encode(["activatedAt": ISO8601DateFormatter().string(from: Date())])
        try lockData.write(to: runtimeLockURL, options: [.atomic])
        return hadExistingLock
    }

    public func clearRuntimeLock() throws {
        try removeIfPresent(runtimeLockURL)
    }

    public func upsert(_ transfer: CoreTransfer) throws {
        try prepareDirectories()

        let existingRecord = try? loadRecord(from: metadataURL(for: transfer.id))
        if transfer.status != .completed || existingRecord?.completedFileName == nil {
            try preparePartFile(for: transfer)
        }

        let chunkMap = existingRecord?.chunkMap.fileSizeInBytes == transfer.sizeInBytes
            ? existingRecord?.chunkMap
            : nil
        let timestamp = Date()
        let record = CoreTransferRecord(
            transfer: transfer,
            partFileName: partFileURL(for: transfer.id).lastPathComponent,
            completedFileName: existingRecord?.completedFileName,
            verifiedHash: existingRecord?.verifiedHash,
            verifiedPartHashes: chunkMap == nil ? [] : existingRecord?.verifiedPartHashes ?? [],
            peerSourceBookmarks: existingRecord?.peerSourceBookmarks ?? [],
            peerInflightBookmarks: existingRecord?.peerInflightBookmarks ?? [],
            peerChunkRetryBookmarks: existingRecord?.peerChunkRetryBookmarks ?? [],
            chunkMap: chunkMap ?? CoreChunkMap(fileSizeInBytes: transfer.sizeInBytes),
            createdAt: existingRecord?.createdAt ?? timestamp,
            updatedAt: timestamp
        )

        try save(record)
    }

    public func writeBlock(transferID: UUID, offset: UInt64, data: Data) throws -> CoreTransferRecord {
        var record = try loadRecord(for: transferID)
        let length = UInt64(data.count)

        guard offset <= record.transfer.sizeInBytes,
              length <= record.transfer.sizeInBytes - offset else {
            throw CoreTransferStoreError.blockOutOfBounds(
                offset: offset,
                length: length,
                fileSize: record.transfer.sizeInBytes
            )
        }

        let fileHandle = try FileHandle(forWritingTo: partFileURL(for: transferID))
        defer {
            try? fileHandle.close()
        }

        try fileHandle.seek(toOffset: offset)
        try fileHandle.write(contentsOf: data)

        clearVerifiedPartHashesOverlappingWrite(&record, offset: offset, length: length)
        record.chunkMap.markWritten(offset: offset, length: length)
        record.transfer.completedBytes = record.chunkMap.completedBytes
        try verifyCompletedPartHashes(&record)
        if record.transfer.status != .failed,
           record.transfer.completedBytes >= record.transfer.sizeInBytes {
            record.transfer.downloadSpeedBytesPerSecond = 0
            if record.completedFileName == nil {
                try verifyAndPromoteCompletedPartFile(&record)
            }
        }
        record.updatedAt = Date()
        try save(record)

        return record
    }

    public func reconcileTransferMetadata(_ transfer: CoreTransfer) throws -> CoreTransferRecord {
        var record = try loadRecord(for: transfer.id)
        record.transfer = transfer
        record.transfer.completedBytes = record.chunkMap.completedBytes
        try verifyCompletedPartHashes(&record)
        if record.transfer.status != .failed,
           record.transfer.completedBytes >= record.transfer.sizeInBytes,
           record.completedFileName == nil {
            record.transfer.downloadSpeedBytesPerSecond = 0
            try verifyAndPromoteCompletedPartFile(&record)
        }
        record.updatedAt = Date()
        try save(record)
        return record
    }

    public func updatePeerSourceBookmarks(
        transferID: UUID,
        bookmarks: [CorePeerSourceBookmark]
    ) throws -> CoreTransferRecord {
        var record = try loadRecord(for: transferID)
        record.peerSourceBookmarks = bookmarks
        record.updatedAt = Date()
        try save(record)
        return record
    }

    public func updatePeerInflightBookmarks(
        transferID: UUID,
        bookmarks: [CorePeerInflightBookmark]
    ) throws -> CoreTransferRecord {
        var record = try loadRecord(for: transferID)
        record.peerInflightBookmarks = bookmarks
        record.updatedAt = Date()
        try save(record)
        return record
    }

    public func updatePeerChunkRetryBookmarks(
        transferID: UUID,
        bookmarks: [CorePeerChunkRetryBookmark]
    ) throws -> CoreTransferRecord {
        var record = try loadRecord(for: transferID)
        record.peerChunkRetryBookmarks = bookmarks
        record.updatedAt = Date()
        try save(record)
        return record
    }

    public func remove(_ transfer: CoreTransfer) throws {
        let record = try? loadRecord(for: transfer.id)
        try removeIfPresent(metadataURL(for: transfer.id))
        try removeIfPresent(partFileURL(for: transfer.id))

        if let record, let completedFileURL = completedFileURL(for: record) {
            try removeIfPresent(completedFileURL)
        }
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: incomingDirectory, withIntermediateDirectories: true)
    }

    private func preparePartFile(for transfer: CoreTransfer) throws {
        let url = partFileURL(for: transfer.id)

        if fileManager.fileExists(atPath: url.path) == false {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: url)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.truncate(atOffset: transfer.sizeInBytes)
    }

    private func loadRecord(from url: URL) throws -> CoreTransferRecord {
        let data = try Data(contentsOf: url)
        return try decoder.decode(CoreTransferRecord.self, from: data)
    }

    private func save(_ record: CoreTransferRecord) throws {
        let data = try encoder.encode(record)
        try data.write(to: metadataURL(for: record.transfer.id), options: [.atomic])
    }

    private func clearVerifiedPartHashesOverlappingWrite(
        _ record: inout CoreTransferRecord,
        offset: UInt64,
        length: UInt64
    ) {
        guard length > 0, record.verifiedPartHashes.isEmpty == false else {
            return
        }

        let writeEndOffset = offset + length
        for chunk in record.chunkMap.chunks {
            guard chunk.index < record.verifiedPartHashes.count else {
                continue
            }

            let chunkEndOffset = chunk.offset + chunk.length
            if writeEndOffset > chunk.offset, offset < chunkEndOffset {
                record.verifiedPartHashes[chunk.index] = nil
            }
        }
    }

    private func verifyCompletedPartHashes(_ record: inout CoreTransferRecord) throws {
        guard record.transfer.partHashes.isEmpty == false else {
            return
        }

        let chunks = record.chunkMap.chunks
        if record.verifiedPartHashes.count < chunks.count {
            record.verifiedPartHashes.append(
                contentsOf: [String?](repeating: nil, count: chunks.count - record.verifiedPartHashes.count)
            )
        }

        for chunk in chunks where chunk.status == .complete {
            guard record.transfer.partHashes.indices.contains(chunk.index),
                  record.verifiedPartHashes[chunk.index] == nil else {
                continue
            }

            let chunkData = try readPartData(
                for: record.transfer.id,
                offset: chunk.offset,
                length: chunk.length
            )
            let actualHash = ED2KHash.hash(data: chunkData)
            let expectedHash = record.transfer.partHashes[chunk.index]

            guard actualHash == expectedHash else {
                record.transfer.status = .failed
                record.transfer.downloadSpeedBytesPerSecond = 0
                return
            }

            record.verifiedPartHashes[chunk.index] = actualHash
        }
    }

    private func verifyAndPromoteCompletedPartFile(_ record: inout CoreTransferRecord) throws {
        let actualHash = try ED2KHash.hash(fileAt: partFileURL(for: record.transfer.id))
        record.verifiedHash = actualHash

        if actualHash != record.transfer.ed2kHash {
            record.transfer.status = .failed
            return
        }

        record.transfer.status = .completed
        record.completedFileName = try promoteCompletedPartFile(for: record)
    }

    private func readPartData(for id: UUID, offset: UInt64, length: UInt64) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: partFileURL(for: id))
        defer {
            try? fileHandle.close()
        }

        try fileHandle.seek(toOffset: offset)
        return try fileHandle.read(upToCount: Int(length)) ?? Data()
    }

    private func promoteCompletedPartFile(for record: CoreTransferRecord) throws -> String {
        try prepareDirectories()

        let sourceURL = partFileURL(for: record.transfer.id)
        let fileName = uniqueIncomingFileName(for: record.transfer)
        let destinationURL = incomingDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } else if fileManager.fileExists(atPath: destinationURL.path) == false {
            fileManager.createFile(atPath: destinationURL.path, contents: nil)
        }

        return fileName
    }

    private func uniqueIncomingFileName(for transfer: CoreTransfer) -> String {
        let sanitizedFileName = sanitizedIncomingFileName(for: transfer)
        var candidate = sanitizedFileName
        var index = 2

        while fileManager.fileExists(atPath: incomingDirectory.appendingPathComponent(candidate).path) {
            candidate = numberedFileName(sanitizedFileName, index: index)
            index += 1
        }

        return candidate
    }

    private func sanitizedIncomingFileName(for transfer: CoreTransfer) -> String {
        let forbiddenCharacters = CharacterSet(charactersIn: "/:")
        let trimmedFileName = transfer.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathSafeName = trimmedFileName
            .components(separatedBy: forbiddenCharacters)
            .filter { $0.isEmpty == false }
            .joined(separator: "_")

        let fallbackName = transfer.id.uuidString
        let fileName = pathSafeName.isEmpty ? fallbackName : pathSafeName

        return URL(fileURLWithPath: fileName).lastPathComponent
    }

    private func numberedFileName(_ fileName: String, index: Int) -> String {
        let nsFileName = fileName as NSString
        let fileExtension = nsFileName.pathExtension
        let baseName = nsFileName.deletingPathExtension

        guard fileExtension.isEmpty == false else {
            return "\(baseName) \(index)"
        }

        return "\(baseName) \(index).\(fileExtension)"
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}
