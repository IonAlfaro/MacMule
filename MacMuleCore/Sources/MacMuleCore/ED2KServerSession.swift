import Foundation

public struct ED2KServerSessionConfiguration: Equatable, Sendable {
    public var endpoint: ED2KServerEndpoint
    public var userHash: Data
    public var clientID: UInt32
    public var tcpPort: UInt16
    public var nickname: String
    public var protocolVersion: UInt32
    public var flags: UInt32

    public init(
        endpoint: ED2KServerEndpoint,
        userHash: Data,
        clientID: UInt32 = 0,
        tcpPort: UInt16 = 4662,
        nickname: String = "MacMule",
        protocolVersion: UInt32 = ED2KLoginRequest.defaultProtocolVersion,
        flags: UInt32 = ED2KLoginRequest.defaultCompressionFlags
    ) {
        self.endpoint = endpoint
        self.userHash = userHash
        self.clientID = clientID
        self.tcpPort = tcpPort
        self.nickname = nickname
        self.protocolVersion = protocolVersion
        self.flags = flags
    }

    public func loginRequest() throws -> ED2KLoginRequest {
        try ED2KLoginRequest(
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            nickname: nickname,
            protocolVersion: protocolVersion,
            flags: flags
        )
    }
}

public enum ED2KServerSessionEvent: Equatable, Sendable {
    case outgoingLogin(ED2KPacket)
    case idChange(ED2KIDChange)
    case serverMessage(ED2KServerMessage)
    case serverStatus(ED2KServerStatus)
    case serverIdentity(ED2KServerIdentity)
    case serverList([ED2KServerEndpoint])
    case searchResults([ED2KSearchResult])
    case foundSources(ED2KFoundSources)
    case callbackRequested(ED2KPeerEndpoint)
    case callbackFailed
    case unhandledPacket(ED2KPacket)
}

public struct ED2KServerSession: Sendable {
    public let configuration: ED2KServerSessionConfiguration

    private var streamDecoder = ED2KPacketStreamDecoder()

    public var bufferedByteCount: Int {
        streamDecoder.bufferedByteCount
    }

    public init(configuration: ED2KServerSessionConfiguration) {
        self.configuration = configuration
    }

    public func loginPacket() throws -> ED2KPacket {
        try configuration.loginRequest().packet()
    }

    public func loginBytes() throws -> Data {
        try loginPacket().encoded()
    }

    public func loginEvent() throws -> ED2KServerSessionEvent {
        try .outgoingLogin(loginPacket())
    }

    public func searchPacket(query: String) throws -> ED2KPacket {
        try ED2KSearchRequest(query: query).packet()
    }

    public func emptyOfferFilesPacket() -> ED2KPacket {
        ED2KPacket(opcode: .offerFiles, payload: Data([0x00, 0x00, 0x00, 0x00]))
    }

    public func offerFilesPacket(fileHashes: [Data]) -> ED2KPacket {
        var payload = Data()
        var count = UInt32(fileHashes.count).littleEndian
        withUnsafeBytes(of: &count) { payload.append(contentsOf: $0) }
        for hash in fileHashes {
            payload.append(hash)
        }
        return ED2KPacket(opcode: .offerFiles, payload: payload)
    }

    public func sourceRequestPacket(fileHash: Data, fileSizeInBytes: UInt64) throws -> ED2KPacket {
        try ED2KSourceRequest(fileHash: fileHash, fileSizeInBytes: fileSizeInBytes).packet()
    }

    public func callbackRequestPacket(clientID: UInt32) -> ED2KPacket {
        ED2KServerCallbackRequest(clientID: clientID).packet()
    }

    public mutating func receive(_ data: Data) throws -> [ED2KServerSessionEvent] {
        let packets = try streamDecoder.append(data)
        return try packets.map { packet in
            do {
                return try event(for: packet)
            } catch let packetError as ED2KPacketError {
                throw ED2KPacketError.invalidPayload(
                    "opcode 0x\(String(format: "%02X", packet.opcode)): \(packetError.localizedDescription)"
                )
            }
        }
    }

    private func event(for packet: ED2KPacket) throws -> ED2KServerSessionEvent {
        switch packet.opcode {
        case ED2KPacketOpcode.idChange.rawValue:
            return .idChange(try ED2KIDChangeDecoder.decodeIDChangePayload(packet.payload))
        case ED2KPacketOpcode.serverMessage.rawValue:
            return .serverMessage(try ED2KServerMessageDecoder.decodeServerMessagePayload(packet.payload))
        case ED2KPacketOpcode.serverStatus.rawValue:
            return .serverStatus(try ED2KServerStatusDecoder.decodeServerStatusPayload(packet.payload))
        case ED2KPacketOpcode.serverIdent.rawValue:
            return .serverIdentity(try ED2KServerIdentityDecoder.decodeServerIdentPayload(packet.payload))
        case ED2KPacketOpcode.serverList.rawValue:
            return .serverList(try ED2KServerListDecoder.decodeServerListPayload(packet.payload))
        case ED2KPacketOpcode.search.rawValue, ED2KPacketOpcode.searchResults.rawValue:
            return .searchResults(try ED2KSearchResultDecoder.decodeSearchResultPayload(packet.payload))
        case ED2KPacketOpcode.foundSources.rawValue:
            return .foundSources(try ED2KFoundSourcesDecoder.decodeFoundSourcesPayload(packet.payload))
        case ED2KPacketOpcode.foundSourcesObfuscated.rawValue:
            return .foundSources(try ED2KFoundSourcesDecoder.decodeObfuscatedFoundSourcesPayload(packet.payload))
        case ED2KPacketOpcode.callbackRequested.rawValue:
            return .callbackRequested(try ED2KCallbackRequestedDecoder.decodeCallbackRequestedPayload(packet.payload))
        case ED2KPacketOpcode.callbackFailed.rawValue:
            return .callbackFailed
        default:
            return .unhandledPacket(packet)
        }
    }
}

public enum ED2KCallbackRequestedDecoder {
    public static func decodeCallbackRequestedPayload(_ payload: Data) throws -> ED2KPeerEndpoint {
        var reader = ED2KBinaryReader(data: payload)
        let octets = try reader.readBytes(count: 4)
        let port = try reader.readUInt16LittleEndian()

        if reader.remainingByteCount >= 17 {
            _ = try reader.readUInt8()
            _ = try reader.readData(count: 16)
        }

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("callback requested payload has trailing bytes")
        }

        return ED2KPeerEndpoint(
            host: octets.map(String.init).joined(separator: "."),
            port: port
        )
    }
}
