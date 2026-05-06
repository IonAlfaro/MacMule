import Foundation

public final class CoreSharedFileList: @unchecked Sendable {

    public struct SharedFileEntry: Equatable, Sendable, Codable {
        public var filePath: String
        public var fileName: String
        public var fileSize: UInt64
        public var ed2kHash: Data
        public var partHashes: [Data]
        public var requests: Int
        public var uploadedBytes: UInt64
        public var sharedAt: Date
        public var lastRequestedAt: Date?

        public init(
            filePath: String,
            fileName: String,
            fileSize: UInt64,
            ed2kHash: Data,
            partHashes: [Data] = [],
            requests: Int = 0,
            uploadedBytes: UInt64 = 0,
            sharedAt: Date = Date(),
            lastRequestedAt: Date? = nil
        ) {
            self.filePath = filePath
            self.fileName = fileName
            self.fileSize = fileSize
            self.ed2kHash = ed2kHash
            self.partHashes = partHashes
            self.requests = requests
            self.uploadedBytes = uploadedBytes
            self.sharedAt = sharedAt
            self.lastRequestedAt = lastRequestedAt
        }
    }

    private let lock = NSLock()
    private var sharedFiles: [Data: SharedFileEntry] = [:]
    private var sharedDirectories: Set<String> = []

    public init(sharedDirectories: [String] = []) {
        self.sharedDirectories = Set(sharedDirectories)
    }

    public func addSharedDirectory(_ path: String) {
        withLock { sharedDirectories.insert(path) }
    }

    public func removeSharedDirectory(_ path: String) {
        withLock { sharedDirectories.remove(path) }
    }

    public func scanDirectories() async throws -> [SharedFileEntry] {
        let directories = withLock { sharedDirectories }
        var newEntries: [SharedFileEntry] = []

        for dir in directories {
            let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      resourceValues.isRegularFile == true,
                      let fileSize = resourceValues.fileSize else { continue }

                let hash = try await computeHash(for: fileURL)
                let entry = SharedFileEntry(
                    filePath: fileURL.path,
                    fileName: fileURL.lastPathComponent,
                    fileSize: UInt64(fileSize),
                    ed2kHash: hash
                )
                newEntries.append(entry)
            }
        }

        withLock {
            for entry in newEntries {
                sharedFiles[entry.ed2kHash] = entry
            }
        }

        return newEntries
    }

    public func allSharedFiles() -> [SharedFileEntry] {
        withLock { Array(sharedFiles.values).sorted { $0.fileName < $1.fileName } }
    }

    public func findFile(byHash hash: Data) -> SharedFileEntry? {
        withLock { sharedFiles[hash] }
    }

    public func findFile(byPath path: String) -> SharedFileEntry? {
        withLock { sharedFiles.values.first { $0.filePath == path } }
    }

    public func recordRequest(fileHash: Data, bytes: UInt64) {
        withLock {
            guard var entry = sharedFiles[fileHash] else { return }
            entry.requests += 1
            entry.uploadedBytes += bytes
            entry.lastRequestedAt = Date()
            sharedFiles[fileHash] = entry
        }
    }

    public func addFile(_ entry: SharedFileEntry) {
        withLock { sharedFiles[entry.ed2kHash] = entry }
    }

    public func removeFile(fileHash: Data) {
        withLock { sharedFiles.removeValue(forKey: fileHash) }
    }

    public var count: Int {
        withLock { sharedFiles.count }
    }

    private func computeHash(for fileURL: URL) async throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var hasher = FileHasher()
        let chunkSize = 9_728_000

        while true {
            guard let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(chunk)
        }

        return hasher.finalize()
    }

    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}

private struct FileHasher {
    private var a: UInt32 = 0x67452301
    private var b: UInt32 = 0xEFCDAB89
    private var c: UInt32 = 0x98BADCFE
    private var d: UInt32 = 0x10325476
    private var partHashes: [Data] = []
    private var partA: UInt32 = 0x67452301
    private var partB: UInt32 = 0xEFCDAB89
    private var partC: UInt32 = 0x98BADCFE
    private var partD: UInt32 = 0x10325476
    private var currentPartSize: Int = 0
    private let partSize = 9_728_000
    private var totalBytes: Int = 0

    mutating func update(_ data: Data) {
        totalBytes += data.count
        var consumed = 0

        while consumed < data.count {
            let remaining = min(data.count - consumed, partSize - currentPartSize)
            let slice = data.subdata(in: consumed ..< (consumed + remaining))

            processSlice(slice, stateA: &partA, stateB: &partB, stateC: &partC, stateD: &partD)
            currentPartSize += remaining
            consumed += remaining

            if currentPartSize >= partSize {
                let hash = finalizeState(partA, partB, partC, partD)
                partHashes.append(hash)
                processSlice(hash, stateA: &a, stateB: &b, stateC: &c, stateD: &d)
                (partA, partB, partC, partD) = (0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476)
                currentPartSize = 0
            }
        }
    }

    mutating func finalize() -> Data {
        if totalBytes <= partSize {
            return finalizeState(partA, partB, partC, partD)
        }

        if currentPartSize > 0 {
            let hash = finalizeState(partA, partB, partC, partD)
            var ra = a, rb = b, rc = c, rd = d
            processSlice(hash, stateA: &ra, stateB: &rb, stateC: &rc, stateD: &rd)
            a = ra; b = rb; c = rc; d = rd
            partHashes.append(hash)
        }

        if partHashes.count == 1 {
            return partHashes[0]
        }

        return finalizeState(a, b, c, d)
    }
}

private func processSlice(_ data: Data, stateA: inout UInt32, stateB: inout UInt32, stateC: inout UInt32, stateD: inout UInt32) {
    var a = stateA, b = stateB, c = stateC, d = stateD
    let padded = md4Pad(data)
    var x = [UInt32](repeating: 0, count: 16)

    for i in stride(from: 0, to: padded.count, by: 64) {
        for j in 0 ..< 16 {
            let offset = i + j * 4
            x[j] = UInt32(padded[offset])
                | (UInt32(padded[offset + 1]) << 8)
                | (UInt32(padded[offset + 2]) << 16)
                | (UInt32(padded[offset + 3]) << 24)
        }

        let origA = a
        let origB = b
        let origC = c
        let origD = d

        for j in [0, 4, 8, 12] {
            a = rotateLeft(a &+ md4f(b, c, d) &+ x[j], by: 3)
            d = rotateLeft(d &+ md4f(a, b, c) &+ x[j + 1], by: 3)
            c = rotateLeft(c &+ md4f(d, a, b) &+ x[j + 2], by: 3)
            b = rotateLeft(b &+ md4f(c, d, a) &+ x[j + 3], by: 3)
        }

        for j in [0, 1, 2, 3] {
            a = rotateLeft(a &+ md4g(b, c, d) &+ x[j] &+ 0x5A827999, by: 7)
            d = rotateLeft(d &+ md4g(a, b, c) &+ x[j + 4] &+ 0x5A827999, by: 7)
            c = rotateLeft(c &+ md4g(d, a, b) &+ x[j + 8] &+ 0x5A827999, by: 7)
            b = rotateLeft(b &+ md4g(c, d, a) &+ x[j + 12] &+ 0x5A827999, by: 7)
        }

        for j in [0, 2, 1, 3] {
            let off = j * 4
            a = rotateLeft(a &+ md4h(b, c, d) &+ x[off] &+ 0x6ED9EBA1, by: 11)
            d = rotateLeft(d &+ md4h(a, b, c) &+ x[off + 2] &+ 0x6ED9EBA1, by: 11)
            c = rotateLeft(c &+ md4h(d, a, b) &+ x[off + 1] &+ 0x6ED9EBA1, by: 11)
            b = rotateLeft(b &+ md4h(c, d, a) &+ x[off + 3] &+ 0x6ED9EBA1, by: 11)
        }

        a = a &+ origA
        b = b &+ origB
        c = c &+ origC
        d = d &+ origD
    }

    stateA = a
    stateB = b
    stateC = c
    stateD = d
}

private func finalizeState(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> Data {
    var result = Data(count: 16)
    result.withUnsafeMutableBytes { buf in
        buf.storeBytes(of: a.littleEndian, toByteOffset: 0, as: UInt32.self)
        buf.storeBytes(of: b.littleEndian, toByteOffset: 4, as: UInt32.self)
        buf.storeBytes(of: c.littleEndian, toByteOffset: 8, as: UInt32.self)
        buf.storeBytes(of: d.littleEndian, toByteOffset: 12, as: UInt32.self)
    }
    return result
}

private func md4f(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (~x & z) }
private func md4g(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (x & z) | (y & z) }
private func md4h(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ y ^ z }

private func rotateLeft(_ value: UInt32, by amount: UInt32) -> UInt32 {
    (value << amount) | (value >> (32 - amount))
}

private func md4Pad(_ data: Data) -> Data {
    var padded = data
    let bitLength = UInt64(data.count) * 8
    padded.append(0x80)
    while padded.count % 64 != 56 {
        padded.append(0)
    }
    padded.append(contentsOf: withUnsafeBytes(of: bitLength.littleEndian) { Data($0) })
    return padded
}
