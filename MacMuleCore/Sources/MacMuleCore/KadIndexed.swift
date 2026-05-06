import Foundation

public final class KadIndexed: @unchecked Sendable {
    private let lock = NSLock()

    private struct KeywordEntry: Codable, Equatable, Sendable {
        var fileHash: Data
        var fileName: String
        var fileSize: UInt64
        var sourceID: KadUInt128
        var publishedAt: Date
    }

    private struct SourceEntry: Codable, Equatable, Sendable {
        var contact: KadContact
        var fileName: String
        var fileSize: UInt64
        var publishedAt: Date
    }

    private struct NotesEntry: Codable, Equatable, Sendable {
        var fileName: String
        var rating: UInt8
        var comment: String?
        var sourceID: KadUInt128
        var publishedAt: Date
    }

    private var keywords: [String: [KeywordEntry]] = [:]
    private var sources: [String: [SourceEntry]] = [:]
    private var notes: [String: [NotesEntry]] = [:]

    public init() {}

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public func addKeyword(
        keyword: String,
        fileHash: Data,
        fileName: String,
        fileSize: UInt64,
        sourceID: KadUInt128
    ) {
        lock.lock()
        defer { lock.unlock() }

        let entry = KeywordEntry(
            fileHash: fileHash,
            fileName: fileName,
            fileSize: fileSize,
            sourceID: sourceID,
            publishedAt: Date()
        )

        let lower = keyword.lowercased()
        var entries = keywords[lower] ?? []
        entries.removeAll { $0.fileHash == fileHash }
        entries.append(entry)
        entries = Array(entries.suffix(KadConstants.maxKeywordResults))
        keywords[lower] = entries
    }

    public func searchKeyword(_ keyword: String) -> [KadKeywordResult] {
        lock.lock()
        defer { lock.unlock() }

        return (keywords[keyword.lowercased()] ?? [])
            .sorted { $0.publishedAt > $1.publishedAt }
            .map { entry in
                KadKeywordResult(
                    fileHash: entry.fileHash,
                    fileName: entry.fileName,
                    fileSize: entry.fileSize
                )
            }
    }

    public func addSource(
        fileHash: Data,
        contact: KadContact,
        fileName: String,
        fileSize: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }

        let entry = SourceEntry(
            contact: contact,
            fileName: fileName,
            fileSize: fileSize,
            publishedAt: Date()
        )

        let key = Self.hexString(fileHash)
        var entries = sources[key] ?? []
        entries.removeAll { $0.contact.nodeID == contact.nodeID }
        entries.append(entry)
        entries = Array(entries.suffix(KadConstants.maxSourceResults))
        sources[key] = entries
    }

    public func searchSources(fileHash: Data) -> [KadSourceResult] {
        lock.lock()
        defer { lock.unlock() }

        return (sources[Self.hexString(fileHash)] ?? [])
            .sorted { $0.publishedAt > $1.publishedAt }
            .map { entry in
                KadSourceResult(
                    contact: entry.contact,
                    fileName: entry.fileName,
                    fileSize: entry.fileSize
                )
            }
    }

    public func addNote(
        fileHash: Data,
        fileName: String,
        rating: UInt8,
        comment: String?,
        sourceID: KadUInt128
    ) {
        lock.lock()
        defer { lock.unlock() }

        let entry = NotesEntry(
            fileName: fileName,
            rating: rating,
            comment: comment,
            sourceID: sourceID,
            publishedAt: Date()
        )

        let key = Self.hexString(fileHash)
        var entries = notes[key] ?? []
        entries.removeAll { $0.sourceID == sourceID }
        entries.append(entry)
        entries = Array(entries.suffix(KadConstants.maxNotesResults))
        notes[key] = entries
    }

    public func searchNotes(fileHash: Data) -> [KadNoteResult] {
        lock.lock()
        defer { lock.unlock() }

        return (notes[Self.hexString(fileHash)] ?? [])
            .sorted { $0.publishedAt > $1.publishedAt }
            .map { entry in
                KadNoteResult(
                    fileName: entry.fileName,
                    rating: entry.rating,
                    comment: entry.comment
                )
            }
    }

    public func expireEntries() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()

        for (key, entries) in keywords {
            keywords[key] = entries.filter {
                now.timeIntervalSince($0.publishedAt) < KadConstants.keywordTTL
            }
        }
        keywords = keywords.filter { !$0.value.isEmpty }

        for (key, entries) in sources {
            sources[key] = entries.filter {
                now.timeIntervalSince($0.publishedAt) < KadConstants.sourceTTL
            }
        }
        sources = sources.filter { !$0.value.isEmpty }

        for (key, entries) in notes {
            notes[key] = entries.filter {
                now.timeIntervalSince($0.publishedAt) < KadConstants.notesTTL
            }
        }
        notes = notes.filter { !$0.value.isEmpty }
    }

    public var stats: KadIndexedStats {
        lock.lock()
        defer { lock.unlock() }

        var totalSources = 0
        for (_, entries) in sources {
            totalSources += entries.count
        }

        return KadIndexedStats(
            keywordCount: keywords.count,
            sourceCount: totalSources,
            notesCount: notes.count
        )
    }
}

public struct KadKeywordResult: Equatable, Sendable, Codable {
    public var fileHash: Data
    public var fileName: String
    public var fileSize: UInt64

    public init(fileHash: Data, fileName: String, fileSize: UInt64) {
        self.fileHash = fileHash
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

public struct KadSourceResult: Equatable, Sendable, Codable {
    public var contact: KadContact
    public var fileName: String
    public var fileSize: UInt64

    public init(contact: KadContact, fileName: String, fileSize: UInt64) {
        self.contact = contact
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

public struct KadNoteResult: Equatable, Sendable, Codable {
    public var fileName: String
    public var rating: UInt8
    public var comment: String?

    public init(fileName: String, rating: UInt8, comment: String?) {
        self.fileName = fileName
        self.rating = rating
        self.comment = comment
    }
}

public struct KadIndexedStats: Equatable, Sendable, Codable {
    public var keywordCount: Int
    public var sourceCount: Int
    public var notesCount: Int

    public init(keywordCount: Int, sourceCount: Int, notesCount: Int) {
        self.keywordCount = keywordCount
        self.sourceCount = sourceCount
        self.notesCount = notesCount
    }
}
