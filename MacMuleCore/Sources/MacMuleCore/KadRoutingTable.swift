import Foundation

public final class KadRoutingTable: @unchecked Sendable {
    private let lock = NSLock()
    private var buckets: [KadRoutingBin]
    private var selfNodeID: KadUInt128

    public init(selfNodeID: KadUInt128) {
        self.selfNodeID = selfNodeID
        self.buckets = [KadRoutingBin(depth: 0)]
    }

    public func updateSelfNodeID(_ nodeID: KadUInt128) {
        lock.lock()
        selfNodeID = nodeID
        lock.unlock()
    }

    public var currentSelfNodeID: KadUInt128 {
        lock.lock()
        defer { lock.unlock() }
        return selfNodeID
    }

    public func addContact(_ contact: KadContact) -> KadRoutingBinInsertResult {
        lock.lock()
        defer { lock.unlock() }

        let distance = contact.distance(to: selfNodeID)
        let prefixBits = 128 - distance.bitCount

        guard let bucketIndex = bucketIndex(for: prefixBits) else {
            return .rejectedBucketFull
        }

        let result = buckets[bucketIndex].addContact(contact)

        if buckets[bucketIndex].isFull, bucketIndex < buckets.count - 1 {
            splitBucketIfNeeded(at: bucketIndex)
        }

        return result
    }

    public func removeContact(nodeID: KadUInt128) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let distance = nodeID ^ selfNodeID
        let prefixBits = 128 - distance.bitCount

        guard let bucketIndex = bucketIndex(for: prefixBits) else {
            return false
        }

        return buckets[bucketIndex].removeContact(nodeID: nodeID)
    }

    public func closestContacts(to target: KadUInt128, maxCount: Int = KadConstants.kBucketSize) -> [KadContact] {
        lock.lock()
        defer { lock.unlock() }

        var allContacts: [KadContact] = []
        for bucket in buckets {
            allContacts.append(contentsOf: bucket.contacts)
        }

        return allContacts
            .sorted { a, b in
                a.distance(to: target) < b.distance(to: target)
            }
            .prefix(maxCount)
            .map { $0 }
    }

    public func findContact(nodeID: KadUInt128) -> KadContact? {
        lock.lock()
        defer { lock.unlock() }

        let distance = nodeID ^ selfNodeID
        let prefixBits = 128 - distance.bitCount

        guard let bucketIndex = bucketIndex(for: prefixBits) else {
            return nil
        }

        return buckets[bucketIndex].findContact(nodeID: nodeID)
    }

    public func allContacts() -> [KadContact] {
        lock.lock()
        defer { lock.unlock() }

        return buckets.flatMap { $0.contacts }
    }

    public func bucketStats(for target: KadUInt128) -> [BucketStat] {
        lock.lock()
        defer { lock.unlock() }

        return buckets.enumerated().map { index, bucket in
            let dist = bucket.contacts.first?.distance(to: target) ?? KadUInt128()
            return BucketStat(
                depth: bucket.depth,
                count: bucket.contacts.count,
                maxSize: KadConstants.kBucketSize,
                prefixBits: String(format: "%02x", dist.hi & 0xFF),
                lastChanged: bucket.lastChanged
            )
        }
    }

    public func expireStale() -> [KadContact] {
        lock.lock()
        defer { lock.unlock() }

        var expired: [KadContact] = []
        for i in buckets.indices {
            expired.append(contentsOf: buckets[i].expireStale())
        }
        return expired
    }

    public var totalContacts: Int {
        lock.lock()
        defer { lock.unlock() }
        return buckets.reduce(0) { $0 + $1.contacts.count }
    }

    public var bucketCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buckets.count
    }

    private func bucketIndex(for prefixBits: Int) -> Int? {
        for i in stride(from: buckets.count - 1, through: 0, by: -1) {
            if prefixBits >= buckets[i].depth {
                return i
            }
        }
        return 0
    }

    private func splitBucketIfNeeded(at index: Int) {
        let bucket = buckets[index]
        let newDepth = bucket.depth + 1

        guard bucket.contacts.count >= KadConstants.kBucketSize,
              bucket.depth < 127 else { return }

        var bucketA = KadRoutingBin(depth: newDepth)
        var bucketB = KadRoutingBin(depth: newDepth)

        for contact in bucket.contacts {
            if contact.distance(to: selfNodeID).bitAt(bucket.depth) {
                _ = bucketA.addContact(contact)
            } else {
                _ = bucketB.addContact(contact)
            }
        }

        buckets[index] = bucketA
        buckets.insert(bucketB, at: index)
    }

    public struct BucketStat: Equatable, Sendable, Codable {
        public var depth: Int
        public var count: Int
        public var maxSize: Int
        public var prefixBits: String
        public var lastChanged: Date

        public init(depth: Int, count: Int, maxSize: Int, prefixBits: String, lastChanged: Date) {
            self.depth = depth
            self.count = count
            self.maxSize = maxSize
            self.prefixBits = prefixBits
            self.lastChanged = lastChanged
        }
    }
}
