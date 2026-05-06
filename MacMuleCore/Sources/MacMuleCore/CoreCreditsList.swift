import Foundation

public struct CreditRecord: Equatable, Sendable, Codable {
    public var userHash: Data
    public var uploadedBytes: UInt64
    public var downloadedBytes: UInt64
    public var lastSeen: Date
    public var score: Double

    public init(
        userHash: Data,
        uploadedBytes: UInt64 = 0,
        downloadedBytes: UInt64 = 0,
        lastSeen: Date = Date(),
        score: Double = 1.0
    ) {
        self.userHash = userHash
        self.uploadedBytes = uploadedBytes
        self.downloadedBytes = downloadedBytes
        self.lastSeen = lastSeen
        self.score = score
    }

    public var ratio: Double {
        guard downloadedBytes > 0 else { return 1.0 }
        return Double(uploadedBytes) / Double(downloadedBytes)
    }

    public mutating func addUpload(_ bytes: UInt64) {
        uploadedBytes += bytes
        lastSeen = Date()
        recalculateScore()
    }

    public mutating func addDownload(_ bytes: UInt64) {
        downloadedBytes += bytes
        lastSeen = Date()
        recalculateScore()
    }

    private mutating func recalculateScore() {
        let r = ratio
        if uploadedBytes == 0 { score = 1.0 }
        else if r >= 1.0 { score = 2.0 + min(r - 1.0, 10.0) }
        else { score = r }
    }
}

public final class CoreCreditsList: @unchecked Sendable {
    private let lock = NSLock()
    private var credits: [Data: CreditRecord] = [:]

    public init() {}

    public func getCredit(userHash: Data) -> CreditRecord {
        lock.lock()
        defer { lock.unlock() }

        if let existing = credits[userHash] {
            return existing
        }
        let record = CreditRecord(userHash: userHash)
        credits[userHash] = record
        return record
    }

    public func addUploadBytes(_ bytes: UInt64, for userHash: Data) {
        lock.lock()
        defer { lock.unlock() }

        var record = credits[userHash] ?? CreditRecord(userHash: userHash)
        record.addUpload(bytes)
        credits[userHash] = record
    }

    public func addDownloadBytes(_ bytes: UInt64, for userHash: Data) {
        lock.lock()
        defer { lock.unlock() }

        var record = credits[userHash] ?? CreditRecord(userHash: userHash)
        record.addDownload(bytes)
        credits[userHash] = record
    }

    public func score(for userHash: Data) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return credits[userHash]?.score ?? 1.0
    }

    public func allCredits() -> [CreditRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(credits.values).sorted { $0.score > $1.score }
    }

    public func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return credits.count
    }

    public func save(to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        let records = Array(credits.values)
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let data = try Data(contentsOf: url)
        let records = try JSONDecoder().decode([CreditRecord].self, from: data)

        for record in records {
            credits[record.userHash] = record
        }
    }
}
