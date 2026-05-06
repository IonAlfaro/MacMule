import Foundation

public struct KadRoutingBin: Equatable, Sendable, Codable {
    public var contacts: [KadContact]
    public var lastChanged: Date
    public var depth: Int

    public init(depth: Int) {
        self.contacts = []
        self.lastChanged = Date()
        self.depth = depth
    }

    public var isFull: Bool {
        contacts.count >= KadConstants.kBucketSize
    }

    public var isEmpty: Bool {
        contacts.isEmpty
    }

    public mutating func addContact(_ contact: KadContact) -> KadRoutingBinInsertResult {
        if let existingIndex = contacts.firstIndex(where: { $0.nodeID == contact.nodeID }) {
            contacts[existingIndex] = contact.touch()
            contacts.sort { a, b in
                a.lastSeen > b.lastSeen
            }
            lastChanged = Date()
            return .updated
        }

        if isFull {
            if let oldestIndex = contacts.lastIndex(where: { $0.isExpired }) {
                contacts[oldestIndex] = contact.touch()
                contacts.sort { a, b in
                    a.lastSeen > b.lastSeen
                }
                lastChanged = Date()
                return .replacedExpired
            }
            return .rejectedBucketFull
        }

        contacts.append(contact.touch())
        contacts.sort { a, b in
            a.lastSeen > b.lastSeen
        }
        lastChanged = Date()
        return .inserted
    }

    public mutating func removeContact(nodeID: KadUInt128) -> Bool {
        guard let index = contacts.firstIndex(where: { $0.nodeID == nodeID }) else {
            return false
        }
        contacts.remove(at: index)
        lastChanged = Date()
        return true
    }

    public func findContact(nodeID: KadUInt128) -> KadContact? {
        contacts.first(where: { $0.nodeID == nodeID })
    }

    public mutating func expireStale() -> [KadContact] {
        let stale = contacts.filter { $0.isExpired }
        contacts.removeAll { $0.isExpired }
        if !stale.isEmpty { lastChanged = Date() }
        return stale
    }
}

public enum KadRoutingBinInsertResult: Equatable, Sendable {
    case inserted
    case updated
    case replacedExpired
    case rejectedBucketFull
}
