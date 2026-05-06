import Foundation

public struct ED2KPeerSessionConfiguration: Equatable, Sendable {
    public var userHash: Data
    public var clientID: UInt32
    public var tcpPort: UInt16
    public var nickname: String
    public var version: String
    public var serverEndpoint: ED2KServerEndpoint

    public init(
        userHash: Data,
        clientID: UInt32 = 0,
        tcpPort: UInt16 = 4662,
        nickname: String = "MacMule",
        version: String = "MacMule/0.1",
        serverEndpoint: ED2KServerEndpoint = ED2KServerEndpoint(host: "0.0.0.0", port: 0)
    ) {
        self.userHash = userHash
        self.clientID = clientID
        self.tcpPort = tcpPort
        self.nickname = nickname
        self.version = version
        self.serverEndpoint = serverEndpoint
    }

    public func hello() throws -> ED2KPeerHello {
        try ED2KPeerHello(
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            nickname: nickname,
            version: version,
            serverEndpoint: serverEndpoint
        )
    }
}

public enum ED2KPeerSessionEvent: Equatable, Sendable {
    case outgoingHello(ED2KPacket)
    case outgoingHelloAnswer(ED2KPacket)
    case outgoingFileRequest(ED2KPacket)
    case outgoingSetRequestFileID(ED2KPacket)
    case outgoingStartUploadRequest(ED2KPacket)
    case outgoingSourceExchangeRequest(ED2KPacket)
    case peerHello(ED2KPeerHello)
    case peerHelloAnswer(ED2KPeerHello)
    case partHashSet(ED2KPartHashSet)
    case sourceExchangeAnswer(ED2KPeerSourceExchangeAnswer)
    case partRequest(ED2KPartRequest)
    case sendingPart(ED2KSendingPart)
    case fileRequestAnswerNoFile(Data)
    case acceptUploadRequest
    case queueRank(UInt32)
    case unhandledPacket(ED2KPacket)
}

public struct ED2KPeerSession: Sendable {
    public let configuration: ED2KPeerSessionConfiguration

    private var streamDecoder = ED2KPacketStreamDecoder()

    public var bufferedByteCount: Int {
        streamDecoder.bufferedByteCount
    }

    public init(configuration: ED2KPeerSessionConfiguration) {
        self.configuration = configuration
    }

    public func helloPacket() throws -> ED2KPacket {
        try configuration.hello().packet(opcode: .hello)
    }

    public func helloAnswerPacket() throws -> ED2KPacket {
        try configuration.hello().packet(opcode: .helloAnswer)
    }

    public func helloEvent() throws -> ED2KPeerSessionEvent {
        try .outgoingHello(helloPacket())
    }

    public func helloAnswerEvent() throws -> ED2KPeerSessionEvent {
        try .outgoingHelloAnswer(helloAnswerPacket())
    }

    public func partRequestPacket(fileHash: Data, ranges: [ED2KPartRange]) throws -> ED2KPacket {
        try ED2KPartRequest(fileHash: fileHash, ranges: ranges).packet()
    }

    public func partHashSetRequestPacket(fileHash: Data) throws -> ED2KPacket {
        try ED2KPartHashSetRequest(fileHash: fileHash).packet()
    }

    public func fileRequestPacket(fileHash: Data) throws -> ED2KPacket {
        try ED2KPeerFileCommand(fileHash: fileHash).packet(opcode: .requestFileName)
    }

    public func setRequestFileIDPacket(fileHash: Data) throws -> ED2KPacket {
        try ED2KPeerFileCommand(fileHash: fileHash).packet(opcode: .setRequestFileID)
    }

    public func startUploadRequestPacket(fileHash: Data) throws -> ED2KPacket {
        try ED2KPeerFileCommand(fileHash: fileHash).packet(opcode: .startUploadRequest)
    }

    public func sourceExchangeRequestPacket(fileHash: Data) throws -> ED2KPacket {
        try ED2KPeerSourceExchangeRequest(fileHash: fileHash).packet()
    }

    public mutating func receive(_ data: Data) throws -> [ED2KPeerSessionEvent] {
        let packets = try streamDecoder.append(data)
        return try packets.map(event)
    }

    private func event(for packet: ED2KPacket) throws -> ED2KPeerSessionEvent {
        switch ED2KPeerPacketOpcode(rawValue: packet.opcode) {
        case .hello:
            return .peerHello(try ED2KPeerHelloDecoder.decodePeerHelloPayload(packet.payload, includesHashLength: true))
        case .helloAnswer:
            return .peerHelloAnswer(try ED2KPeerHelloDecoder.decodePeerHelloPayload(packet.payload, includesHashLength: false))
        case .hashSetAnswer:
            return .partHashSet(try ED2KPartHashSetDecoder.decodePartHashSetPayload(packet.payload))
        case .answerSources:
            return .sourceExchangeAnswer(
                try ED2KPeerSourceExchangeDecoder.decodeAnswerSourcesPayload(
                    packet.payload,
                    isSourceExchange2: false
                )
            )
        case .answerSources2:
            return .sourceExchangeAnswer(
                try ED2KPeerSourceExchangeDecoder.decodeAnswerSourcesPayload(
                    packet.payload,
                    isSourceExchange2: true
                )
            )
        case .requestParts:
            return .partRequest(try ED2KPartRequestDecoder.decodePartRequestPayload(packet.payload))
        case .requestPartsI64:
            return .partRequest(try ED2KPartRequestDecoder.decodePartRequestPayload(packet.payload, uses64BitOffsets: true))
        case .sendingPart:
            return .sendingPart(try ED2KSendingPartDecoder.decodeSendingPartPayload(packet.payload))
        case .sendingPartI64:
            return .sendingPart(try ED2KSendingPartDecoder.decodeSendingPartPayload(packet.payload, uses64BitOffsets: true))
        case .compressedPart:
            return .sendingPart(try ED2KSendingPartDecoder.decodeSendingPartPayload(packet.payload, isCompressed: true))
        case .compressedPartI64:
            return .sendingPart(try ED2KSendingPartDecoder.decodeSendingPartPayload(packet.payload, uses64BitOffsets: true, isCompressed: true))
        case .fileRequestAnswerNoFile:
            return .fileRequestAnswerNoFile(packet.payload)
        case .acceptUploadRequest:
            guard packet.payload.isEmpty else {
                return .unhandledPacket(packet)
            }
            return .acceptUploadRequest
        case .queueRank:
            var reader = ED2KBinaryReader(data: packet.payload)
            let rank = try reader.readUInt32LittleEndian()
            guard reader.isAtEnd else {
                return .unhandledPacket(packet)
            }
            return .queueRank(rank)
        default:
            return .unhandledPacket(packet)
        }
    }
}
