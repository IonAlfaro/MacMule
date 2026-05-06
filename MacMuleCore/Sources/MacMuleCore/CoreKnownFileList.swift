import Foundation

public final class CoreKnownFileList: @unchecked Sendable {
    public struct KnownFileEntry: Codable, Equatable, Sendable, Identifiable {
        public var id: String { ed2kHash.hexString }
        public var ed2kHash: Data
        public var fileName: String
        public var fileSize: UInt64
        public var lastSeen: Date
        public var uploadCount: Int
        public var downloadCount: Int
        public var cancelled: Bool

        public init(
            ed2kHash: Data,
            fileName: String,
            fileSize: UInt64,
            lastSeen: Date = Date(),
            uploadCount: Int = 0,
            downloadCount: Int = 0,
            cancelled: Bool = false
        ) {
            self.ed2kHash = ed2kHash
            self.fileName = fileName
            self.fileSize = fileSize
            self.lastSeen = lastSeen
            self.uploadCount = uploadCount
            self.downloadCount = downloadCount
            self.cancelled = cancelled
        }
    }

    private let lock = NSLock()
    private var entries: [Data: KnownFileEntry] = [:]
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([KnownFileEntry].self, from: data)
        for entry in decoded {
            entries[entry.ed2kHash] = entry
        }
    }

    public func save() throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(Array(entries.values))
        try data.write(to: fileURL, options: .atomic)
    }

    public func recordDownload(hash: Data, fileName: String, fileSize: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[hash] {
            entry.downloadCount += 1
            entry.lastSeen = Date()
            entry.fileName = fileName
            entry.cancelled = false
            entries[hash] = entry
        } else {
            entries[hash] = KnownFileEntry(
                ed2kHash: hash,
                fileName: fileName,
                fileSize: fileSize,
                downloadCount: 1
            )
        }
    }

    public func recordUpload(hash: Data) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[hash] {
            entry.uploadCount += 1
            entry.lastSeen = Date()
            entries[hash] = entry
        }
    }

    public func markCancelled(hash: Data) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[hash] {
            entry.cancelled = true
            entries[hash] = entry
        }
    }

    public func isKnown(_ hash: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[hash] != nil
    }

    public func isCancelled(_ hash: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[hash]?.cancelled ?? false
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public var allEntries: [KnownFileEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.values).sorted { $0.lastSeen > $1.lastSeen }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
