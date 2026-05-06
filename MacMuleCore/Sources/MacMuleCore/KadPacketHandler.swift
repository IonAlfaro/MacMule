import Foundation

public final class KadPacketHandler: KadUDPPacketHandler, @unchecked Sendable {
    private weak var service: KadService?
    private weak var indexed: KadIndexed?
    private weak var listener: KadUDPListener?
    private weak var packetTracker: KadPacketTracker?
    private weak var searchManager: KadSearchManager?
    private let logHandler: (@Sendable (String) -> Void)?

    public init(
        service: KadService,
        indexed: KadIndexed,
        listener: KadUDPListener,
        packetTracker: KadPacketTracker,
        searchManager: KadSearchManager,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.service = service
        self.indexed = indexed
        self.listener = listener
        self.packetTracker = packetTracker
        self.searchManager = searchManager
        self.logHandler = logHandler
    }

    public func handleKadPacket(_ data: Data, from endpoint: KadEndpoint) {
        guard data.count >= 18 else {
            log("Kad packet too short: \(data.count) bytes")
            return
        }

        let protocolByte = data[0]
        guard protocolByte == 0xE4 else {
            log("Unknown Kad protocol byte: 0x\(String(format: "%02X", protocolByte))")
            return
        }

        guard let opcode = KadPacketOpcode(rawValue: data[1]) else {
            log("Unknown Kad opcode: 0x\(String(format: "%02X", data[1]))")
            return
        }

        var transactionData = Data(count: 16)
        transactionData.withUnsafeMutableBytes { dest in
            data.copyBytes(to: dest, from: 2..<18)
        }
        let transactionID = KadUInt128(data: transactionData)
        let payload = data.dropFirst(18)

        // Check if this is a response to a pending request
        if opcode.isRequest == false,
           let pending = packetTracker?.matchResponse(opcode: opcode, transaction: transactionID) {
            handleResponse(opcode: opcode, pending: pending, payload: payload, from: endpoint)
            return
        }

        // Handle incoming requests
        handleRequest(opcode: opcode, transactionID: transactionID, payload: payload, from: endpoint)
    }

    private func handleResponse(opcode: KadPacketOpcode, pending: KadPacketTracker.PendingRequest, payload: Data, from endpoint: KadEndpoint) {
        switch opcode {
        case .helloRes:
            // Extract real NodeID from response (first 16 bytes of payload)
            if payload.count >= 16 {
                let nodeID = KadUInt128(data: payload.prefix(16))
                let contact = KadContact(
                    nodeID: nodeID,
                    ipAddress: endpoint.ipAddress,
                    udpPort: endpoint.port,
                    tcpPort: endpoint.port,
                    kadVersion: 9,
                    verified: true
                )
                service?.addContact(contact)
                log("Kad: PONG from \(endpoint.ipAddress):\(endpoint.port) — NodeID: \(nodeID.hexString.prefix(12))...")
            }

        case .res:
            // Parse returned contacts from FIND_NODE response
            var contacts: [KadContact] = []
            var offset = 0
            while offset + 16 <= payload.count {
                let nodeID = KadUInt128(data: payload.subdata(in: offset..<offset+16))
                let contact = KadContact(
                    nodeID: nodeID,
                    ipAddress: endpoint.ipAddress,
                    udpPort: endpoint.port,
                    tcpPort: endpoint.port,
                    verified: false
                )
                contacts.append(contact)
                service?.addContact(contact)
                offset += 16
            }
            if !contacts.isEmpty {
                log("Kad: received \(contacts.count) contact(s) from FIND_NODE response")
                // Notify lookup coordinator
                if let lookups = service?.lookups {
                    lookups.receivedContacts(contacts, for: pending.transactionID)
                }
            }

        case .searchRes:
            // Parse search result contacts
            var contacts: [KadContact] = []
            var offset = 0
            while offset + 16 <= payload.count {
                let nodeID = KadUInt128(data: payload.subdata(in: offset..<offset+16))
                let contact = KadContact(
                    nodeID: nodeID,
                    ipAddress: endpoint.ipAddress,
                    udpPort: endpoint.port,
                    tcpPort: endpoint.port,
                    verified: false
                )
                contacts.append(contact)
                offset += 16
            }
            if let lookups = service?.lookups {
                lookups.receivedResults(contacts, for: pending.transactionID)
            }

        default:
            break
        }
    }

    private func handleRequest(opcode: KadPacketOpcode, transactionID: KadUInt128, payload: Data, from endpoint: KadEndpoint) {
        switch opcode {
        case .helloReq:
            sendResponse(opcode: .helloRes, transactionID: transactionID, payload: Data(), to: endpoint)

        case .req where payload.count >= 1:
            let searchType = payload[0]
            let searchPayload = payload.dropFirst()

            if searchType == KadSearchType.findNode.rawValue, searchPayload.count >= 16 {
                let target = KadUInt128(data: searchPayload.prefix(16))
                let closest = service?.routingTable.closestContacts(to: target, maxCount: KadConstants.kBucketSize) ?? []
                var responseData = Data()
                for contact in closest {
                    responseData.append(contact.nodeID.data)
                }
                sendResponse(opcode: .res, transactionID: transactionID, payload: responseData, to: endpoint)
            }

        case .searchReq where payload.count >= 1:
            let searchType = payload[0]
            let searchPayload = payload.dropFirst()

            if searchType == KadSearchType.source.rawValue, searchPayload.count >= 16 {
                let fileHash = searchPayload.prefix(16)
                if let results = indexed?.searchSources(fileHash: fileHash) {
                    var responseData = Data()
                    for result in results {
                        responseData.append(result.contact.nodeID.data)
                    }
                    sendResponse(opcode: .searchRes, transactionID: transactionID, payload: responseData, to: endpoint)
                }
            } else if searchType == KadSearchType.keyword.rawValue {
                let keyword = String(decoding: searchPayload, as: UTF8.self)
                if let results = indexed?.searchKeyword(keyword) {
                    var responseData = Data()
                    for result in results {
                        responseData.append(result.fileHash)
                    }
                    sendResponse(opcode: .searchRes, transactionID: transactionID, payload: responseData, to: endpoint)
                }
            }

        case .publishReq where payload.count >= 16:
            // Store the incoming published data
            let key = payload.prefix(16)
            let value = payload.dropFirst(16)
            if let sourceID = service.map({ KadUInt128(data: $0.selfNodeID.data) }) {
                indexed?.addKeyword(
                    keyword: String(decoding: value.prefix(min(value.count, 100)), as: UTF8.self),
                    fileHash: key,
                    fileName: String(decoding: value.prefix(min(value.count, 100)), as: UTF8.self),
                    fileSize: UInt64(value.count),
                    sourceID: sourceID
                )
            }
            sendResponse(opcode: .publishRes, transactionID: transactionID, payload: Data(), to: endpoint)

        default:
            break
        }
    }

    private func sendResponse(opcode: KadPacketOpcode, transactionID: KadUInt128, payload: Data, to endpoint: KadEndpoint) {
        guard let listener = listener else { return }

        var packet = Data()
        packet.append(0xE4)
        packet.append(opcode.rawValue)
        packet.append(transactionID.data)
        packet.append(payload)

        listener.sendPacket(packet, to: endpoint)
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}
