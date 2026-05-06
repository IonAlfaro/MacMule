import Foundation

public final class KadSearchManager: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSearches: [KadUInt128: KadActiveSearch] = [:]

    public init() {}

    public func startSearch(
        id: KadUInt128,
        type: KadSearchType,
        target: KadUInt128,
        searchTerms: Data? = nil
    ) -> KadActiveSearch {
        lock.lock()
        defer { lock.unlock() }

        let search = KadActiveSearch(
            id: id,
            type: type,
            target: target,
            searchTerms: searchTerms,
            startedAt: Date()
        )
        activeSearches[id] = search
        return search
    }

    public func addResults(_ results: [KadSearchResultItem], to searchID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }

        guard var search = activeSearches[searchID] else { return }
        search.addResults(results)
        activeSearches[searchID] = search
    }

    public func addClosestContacts(_ contacts: [KadContact], to searchID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }

        guard var search = activeSearches[searchID] else { return }
        search.addClosestContacts(contacts)
        activeSearches[searchID] = search
    }

    public func completeSearch(_ searchID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }

        guard var search = activeSearches[searchID] else { return }
        search.completedAt = Date()
        activeSearches[searchID] = search
    }

    public func removeSearch(_ searchID: KadUInt128) {
        lock.lock()
        activeSearches.removeValue(forKey: searchID)
        lock.unlock()
    }

    public func getSearch(_ searchID: KadUInt128) -> KadActiveSearch? {
        lock.lock()
        defer { lock.unlock() }
        return activeSearches[searchID]
    }

    public func expireStaleSearches() -> [KadUInt128] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let expired = activeSearches.filter {
            $0.value.completedAt == nil
                && now.timeIntervalSince($0.value.startedAt) > KadConstants.searchLifetime
        }
        for key in expired.keys {
            activeSearches.removeValue(forKey: key)
        }
        return Array(expired.keys)
    }

    public var activeSearchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeSearches.count
    }

    public var allActiveSearches: [KadActiveSearch] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeSearches.values)
    }
}

public struct KadActiveSearch: Equatable, Sendable, Codable {
    public var id: KadUInt128
    public var type: KadSearchType
    public var target: KadUInt128
    public var searchTerms: Data?
    public var startedAt: Date
    public var completedAt: Date?
    public var results: [KadSearchResultItem]
    public var closestContacts: [KadContact]
    public var queriedNodes: Int
    public var responsesReceived: Int

    public init(
        id: KadUInt128,
        type: KadSearchType,
        target: KadUInt128,
        searchTerms: Data? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.target = target
        self.searchTerms = searchTerms
        self.startedAt = startedAt
        self.results = []
        self.closestContacts = []
        self.queriedNodes = 0
        self.responsesReceived = 0
    }

    public var isComplete: Bool {
        completedAt != nil
    }

    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    public mutating func addResults(_ newResults: [KadSearchResultItem]) {
        results.append(contentsOf: newResults)
        responsesReceived += 1
    }

    public mutating func addClosestContacts(_ contacts: [KadContact]) {
        closestContacts.append(contentsOf: contacts)
        queriedNodes += 1
    }
}

public struct KadSearchResultItem: Equatable, Sendable, Codable {
    public var fileHash: Data
    public var fileName: String
    public var fileSize: UInt64
    public var sourceID: KadUInt128?
    public var sourceIP: String?
    public var sourcePort: UInt16?

    public init(
        fileHash: Data,
        fileName: String,
        fileSize: UInt64,
        sourceID: KadUInt128? = nil,
        sourceIP: String? = nil,
        sourcePort: UInt16? = nil
    ) {
        self.fileHash = fileHash
        self.fileName = fileName
        self.fileSize = fileSize
        self.sourceID = sourceID
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
    }
}
