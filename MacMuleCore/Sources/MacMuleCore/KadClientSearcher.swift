import Foundation

public final class KadClientSearcher: @unchecked Sendable {
    private let routingTable: KadRoutingTable
    private let listener: KadUDPListener
    private let packetTracker: KadPacketTracker
    private let logHandler: (@Sendable (String) -> Void)?

    public init(
        routingTable: KadRoutingTable,
        listener: KadUDPListener,
        packetTracker: KadPacketTracker = KadPacketTracker(),
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.routingTable = routingTable
        self.listener = listener
        self.packetTracker = packetTracker
        self.logHandler = logHandler
    }

    public func findClosest(to target: KadUInt128, maxNodes: Int = Int(KadConstants.alpha)) async -> [KadContact] {
        routingTable.closestContacts(to: target, maxCount: maxNodes)
    }

    public func sendFindNode(target: KadUInt128, to contact: KadContact) -> KadUInt128 {
        let transaction = packetTracker.nextID()

        var packet = buildHeader(opcode: .req, transactionID: transaction)
        packet.append(contentsOf: [KadSearchType.findNode.rawValue])
        packet.append(target.data)

        listener.sendPacket(packet, to: contact.endpoint)
        packetTracker.track(
            send: contact.nodeID,
            transaction: transaction,
            expectedResponse: .res
        )

        return transaction
    }

    public func sendFindValue(target: KadUInt128, to contact: KadContact) -> KadUInt128 {
        let transaction = packetTracker.nextID()

        var packet = buildHeader(opcode: .req, transactionID: transaction)
        packet.append(contentsOf: [KadSearchType.findValue.rawValue])
        packet.append(target.data)

        listener.sendPacket(packet, to: contact.endpoint)
        packetTracker.track(
            send: contact.nodeID,
            transaction: transaction,
            expectedResponse: .res
        )

        return transaction
    }

    public func sendStore(target: KadUInt128, value: Data, to contact: KadContact) -> KadUInt128 {
        let transaction = packetTracker.nextID()

        var packet = buildHeader(opcode: .req, transactionID: transaction)
        packet.append(contentsOf: [KadSearchType.store.rawValue])
        packet.append(target.data)
        packet.append(value)

        listener.sendPacket(packet, to: contact.endpoint)
        packetTracker.track(
            send: contact.nodeID,
            transaction: transaction,
            expectedResponse: .res
        )

        return transaction
    }

    public func sendPing(to contact: KadContact) -> KadUInt128 {
        let transaction = packetTracker.nextID()

        let packet = buildHeader(opcode: .helloReq, transactionID: transaction)
        listener.sendPacket(packet, to: contact.endpoint)
        packetTracker.track(
            send: contact.nodeID,
            transaction: transaction,
            expectedResponse: .helloRes
        )

        return transaction
    }

    private func buildHeader(opcode: KadPacketOpcode, transactionID: KadUInt128) -> Data {
        var header = Data()
        header.append(0xE4)
        header.append(opcode.rawValue)
        header.append(transactionID.data)
        return header
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}
