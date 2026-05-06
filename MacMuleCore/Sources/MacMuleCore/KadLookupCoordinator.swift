import Foundation

public final class KadLookupCoordinator: @unchecked Sendable {
    private let routingTable: KadRoutingTable
    private let clientSearcher: KadClientSearcher
    private let logHandler: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var activeLookups: [KadUInt128: ActiveLookup] = [:]

    public init(
        routingTable: KadRoutingTable,
        clientSearcher: KadClientSearcher,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.routingTable = routingTable
        self.clientSearcher = clientSearcher
        self.logHandler = logHandler
    }

    public func findNodes(target: KadUInt128) async -> [KadContact] {
        withLock { activeLookups[target] = ActiveLookup(target: target) }

        let initial = routingTable.closestContacts(to: target, maxCount: Int(KadConstants.alpha))
        if initial.isEmpty {
            log("Kad lookup: no contacts in routing table for target")
            return []
        }

        for contact in initial.prefix(Int(KadConstants.alpha)) {
            let tid = clientSearcher.sendFindNode(target: target, to: contact)
            withLock { activeLookups[target]?.addQueried(contact) }
            _ = tid
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        var all = withLock { activeLookups[target]?.allContacts ?? initial }
        all.append(contentsOf: withLock { activeLookups[target]?.queriedContacts ?? [] })
        all = Array(Set(all))

        let sorted = all.sorted { $0.distance(to: target) < $1.distance(to: target) }

        let remaining = sorted.filter { c in
            !(withLock { activeLookups[target]?.queriedContacts.contains(c) ?? false })
        }

        for contact in remaining.prefix(Int(KadConstants.alpha)) {
            let tid = clientSearcher.sendFindNode(target: target, to: contact)
            withLock { activeLookups[target]?.addQueried(contact) }
            _ = tid
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        let result = withLock { activeLookups[target]?.allContacts ?? [] }
        let finalSorted = result.sorted { $0.distance(to: target) < $1.distance(to: target) }

        withLock { activeLookups.removeValue(forKey: target) }
        return Array(finalSorted.prefix(Int(KadConstants.kBucketSize)))
    }

    public func findValue(target: KadUInt128, searchType: KadSearchType) async -> [KadContact] {
        let closest = await findNodes(target: target)
        return closest.filter { $0.verified }
    }

    public func receivedContacts(_ contacts: [KadContact], for transactionID: KadUInt128) {
        lock.lock()
        for lookup in activeLookups.values {
            for contact in contacts {
                lookup.addContact(contact)
            }
        }
        lock.unlock()
    }

    public func receivedResults(_ contacts: [KadContact], for transactionID: KadUInt128) {
        receivedContacts(contacts, for: transactionID)
    }

    private func log(_ message: String) {
        logHandler?(message)
    }

    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}

private final class ActiveLookup: @unchecked Sendable {
    let target: KadUInt128
    var allContacts: [KadContact] = []
    var queriedContacts: [KadContact] = []
    let lock = NSLock()

    init(target: KadUInt128) {
        self.target = target
    }

    func addContact(_ contact: KadContact) {
        lock.lock()
        if !allContacts.contains(contact) {
            allContacts.append(contact)
        }
        lock.unlock()
    }

    func addQueried(_ contact: KadContact) {
        lock.lock()
        if !queriedContacts.contains(contact) {
            queriedContacts.append(contact)
        }
        lock.unlock()
    }
}
