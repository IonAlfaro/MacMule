import Foundation
import MacMuleZlib

public enum ED2KProtocolByte: UInt8, Codable, Equatable, Sendable {
    case edonkey = 0xE3
    case emule = 0xC5
}

public enum ED2KPacketOpcode: UInt8, Codable, Equatable, Sendable {
    case loginRequest = 0x01
    case offerFiles = 0x15
    case search = 0x16
    case searchResults = 0x33
    case getSources = 0x19
    case callbackRequest = 0x1C
    case serverList = 0x32
    case callbackRequested = 0x35
    case callbackFailed = 0x36
    case serverMessage = 0x38
    case serverStatus = 0x34
    case idChange = 0x40
    case serverIdent = 0x41
    case foundSources = 0x42
    case foundSourcesObfuscated = 0x44
}

public enum ED2KPeerPacketOpcode: UInt8, Codable, Equatable, Sendable {
    case hello = 0x01
    case compressedPart = 0x40
    case sendingPart = 0x46
    case requestParts = 0x47
    case fileRequestAnswerNoFile = 0x48
    case setRequestFileID = 0x4F
    case fileStatus = 0x50
    case hashSetRequest = 0x51
    case hashSetAnswer = 0x52
    case startUploadRequest = 0x54
    case acceptUploadRequest = 0x55
    case requestFileName = 0x58
    case queueRank = 0x5C
    case requestSources = 0x81
    case answerSources = 0x82
    case requestSources2 = 0x83
    case answerSources2 = 0x84
    case helloAnswer = 0x4C
    case compressedPartI64 = 0xA1
    case sendingPartI64 = 0xA2
    case requestPartsI64 = 0xA3
}

public enum ED2KPacketError: Error, Equatable, LocalizedError {
    case truncatedHeader
    case unsupportedProtocol(UInt8)
    case missingOpcode
    case invalidSize(expected: Int, actual: Int)
    case decompressionFailed
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .truncatedHeader:
            return "eD2k packet header is incomplete."
        case .unsupportedProtocol(let protocolByte):
            return "Unsupported eD2k protocol byte: 0x\(String(format: "%02X", protocolByte))."
        case .missingOpcode:
            return "eD2k packet is missing an opcode."
        case .invalidSize(let expected, let actual):
            return "Invalid eD2k packet size: expected \(expected) bytes, got \(actual)."
        case .decompressionFailed:
            return "Could not decompress packed eD2k packet."
        case .invalidPayload(let message):
            return "Invalid eD2k packet payload: \(message)."
        }
    }
}

private enum ED2KPackedPacketDecoder {
    static let protocolByte: UInt8 = 0xD4
    private static let maxDecodedPayloadSize = 250_000

    static func isSupportedProtocolByte(_ value: UInt8) -> Bool {
        ED2KProtocolByte(rawValue: value) != nil || value == protocolByte
    }

    static func decodePayloadIfNeeded(protocolByteValue: UInt8, payload: Data) throws -> (ED2KProtocolByte, Data) {
        guard protocolByteValue == protocolByte else {
            guard let protocolByte = ED2KProtocolByte(rawValue: protocolByteValue) else {
                throw ED2KPacketError.unsupportedProtocol(protocolByteValue)
            }
            return (protocolByte, payload)
        }

        return (.edonkey, try inflateZlib(payload))
    }

    fileprivate static func inflateZlib(_ data: Data) throws -> Data {
        guard data.isEmpty == false else {
            throw ED2KPacketError.decompressionFailed
        }

        if let output = inflate(data, raw: false) ?? inflate(data, raw: true) {
            return output
        }

        throw ED2KPacketError.decompressionFailed
    }

    private static func inflate(_ data: Data, raw: Bool) -> Data? {
        var output = Data(count: maxDecodedPayloadSize)
        var decodedSize = maxDecodedPayloadSize
        let result = output.withUnsafeMutableBytes { outputBuffer -> Int32 in
            guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return -1
            }

            return data.withUnsafeBytes { inputBuffer -> Int32 in
                guard let inputBase = inputBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }

                return withUnsafeMutablePointer(to: &decodedSize) { decodedSizePointer in
                    macmule_zlib_inflate(
                        inputBase,
                        data.count,
                        outputBase,
                        decodedSizePointer,
                        raw ? 1 : 0
                    )
                }
            }
        }

        guard result == 0, decodedSize > 0 else {
            return nil
        }

        output.removeSubrange(decodedSize..<output.count)
        return output
    }
}

public struct ED2KPacket: Codable, Equatable, Sendable {
    public var protocolByte: ED2KProtocolByte
    public var opcode: UInt8
    public var payload: Data

    public init(
        protocolByte: ED2KProtocolByte = .edonkey,
        opcode: UInt8,
        payload: Data = Data()
    ) {
        self.protocolByte = protocolByte
        self.opcode = opcode
        self.payload = payload
    }

    public init(
        protocolByte: ED2KProtocolByte = .edonkey,
        opcode: ED2KPacketOpcode,
        payload: Data = Data()
    ) {
        self.init(protocolByte: protocolByte, opcode: opcode.rawValue, payload: payload)
    }

    public func encoded() -> Data {
        var data = Data()
        data.append(protocolByte.rawValue)
        data.appendLittleEndian(UInt32(payload.count + 1))
        data.append(opcode)
        data.append(payload)
        return data
    }

    public static func decode(_ data: Data) throws -> ED2KPacket {
        guard data.count >= 5 else {
            throw ED2KPacketError.truncatedHeader
        }

        let protocolByteValue = data[data.startIndex]
        guard ED2KPackedPacketDecoder.isSupportedProtocolByte(protocolByteValue) else {
            throw ED2KPacketError.unsupportedProtocol(protocolByteValue)
        }

        let declaredSize = Int(data.readUInt32LittleEndian(at: 1))
        guard declaredSize >= 1 else {
            throw ED2KPacketError.missingOpcode
        }

        let expectedSize = declaredSize + 5
        guard data.count == expectedSize else {
            throw ED2KPacketError.invalidSize(expected: expectedSize, actual: data.count)
        }

        let opcode = data[data.index(data.startIndex, offsetBy: 5)]
        let payloadStart = data.index(data.startIndex, offsetBy: 6)
        let rawPayload = Data(data[payloadStart..<data.endIndex])
        let (protocolByte, payload) = try ED2KPackedPacketDecoder.decodePayloadIfNeeded(
            protocolByteValue: protocolByteValue,
            payload: rawPayload
        )

        return ED2KPacket(protocolByte: protocolByte, opcode: opcode, payload: payload)
    }
}

public struct ED2KPacketStreamDecoder: Sendable {
    private var buffer = Data()

    public var bufferedByteCount: Int {
        buffer.count
    }

    public init() {}

    public mutating func append(_ data: Data) throws -> [ED2KPacket] {
        guard data.isEmpty == false else {
            return []
        }

        buffer.append(data)
        var packets: [ED2KPacket] = []

        while buffer.count >= 5 {
            let protocolByteValue = buffer[buffer.startIndex]
            guard ED2KPackedPacketDecoder.isSupportedProtocolByte(protocolByteValue) else {
                throw ED2KPacketError.unsupportedProtocol(protocolByteValue)
            }

            let declaredSize = Int(buffer.readUInt32LittleEndian(at: 1))
            guard declaredSize >= 1 else {
                throw ED2KPacketError.missingOpcode
            }

            let packetSize = declaredSize + 5
            guard buffer.count >= packetSize else {
                break
            }

            let packetEndIndex = buffer.index(buffer.startIndex, offsetBy: packetSize)
            let packetData = Data(buffer[buffer.startIndex..<packetEndIndex])
            packets.append(try ED2KPacket.decode(packetData))
            buffer.removeSubrange(buffer.startIndex..<packetEndIndex)
        }

        return packets
    }
}

public enum ED2KTagValue: Equatable, Sendable {
    case string(String)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var uint64Value: UInt64? {
        switch self {
        case .string:
            return nil
        case .uint8(let value):
            return UInt64(value)
        case .uint16(let value):
            return UInt64(value)
        case .uint32(let value):
            return UInt64(value)
        case .uint64(let value):
            return value
        }
    }
}

public struct ED2KTag: Equatable, Sendable {
    public var name: UInt8
    public var value: ED2KTagValue

    public init(name: UInt8, value: ED2KTagValue) {
        self.name = name
        self.value = value
    }

    public func encoded() -> Data {
        var data = Data()

        switch value {
        case .string(let value):
            let valueData = Data(value.utf8)
            data.append(0x02)
            data.appendLittleEndian(UInt16(1))
            data.append(name)
            data.appendLittleEndian(UInt16(valueData.count))
            data.append(valueData)
        case .uint8(let value):
            data.append(0x09)
            data.appendLittleEndian(UInt16(1))
            data.append(name)
            data.append(value)
        case .uint16(let value):
            data.append(0x08)
            data.appendLittleEndian(UInt16(1))
            data.append(name)
            data.appendLittleEndian(value)
        case .uint32(let value):
            data.append(0x03)
            data.appendLittleEndian(UInt16(1))
            data.append(name)
            data.appendLittleEndian(value)
        case .uint64(let value):
            data.append(0x0B)
            data.appendLittleEndian(UInt16(1))
            data.append(name)
            data.appendLittleEndian(value)
        }

        return data
    }
}

public enum ED2KLoginRequestError: Error, Equatable, LocalizedError {
    case invalidUserHashLength(Int)
    case tagCountTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidUserHashLength(let length):
            return "eD2k login user hash must be 16 bytes, got \(length)."
        case .tagCountTooLarge(let count):
            return "eD2k login has too many tags: \(count)."
        }
    }
}

public struct ED2KLoginRequest: Equatable, Sendable {
    public static let defaultProtocolVersion: UInt32 = 60
    public static let serverCapabilityZlib: UInt32 = 0x0001
    public static let serverCapabilityNewTags: UInt32 = 0x0008
    public static let serverCapabilityUnicode: UInt32 = 0x0010
    public static let serverCapabilityLargeFiles: UInt32 = 0x0100
    public static let serverCapabilitySupportCryptLayer: UInt32 = 0x0200
    public static let serverCapabilityRequestCryptLayer: UInt32 = 0x0400
    public static let legacyDefaultServerCapabilityFlags: UInt32 =
        serverCapabilityZlib
        | serverCapabilityNewTags
        | serverCapabilityUnicode
        | serverCapabilityLargeFiles
    public static let defaultServerCapabilityFlags: UInt32 =
        legacyDefaultServerCapabilityFlags
        | serverCapabilitySupportCryptLayer
        | serverCapabilityRequestCryptLayer
    public static let defaultCompressionFlags: UInt32 = defaultServerCapabilityFlags
    public static let defaultMuleVersion: UInt32 = (UInt32(0) << 17) | (UInt32(0x72) << 10) | (UInt32(0) << 7)

    public var userHash: Data
    public var clientID: UInt32
    public var tcpPort: UInt16
    public var tags: [ED2KTag]

    public init(
        userHash: Data,
        clientID: UInt32 = 0,
        tcpPort: UInt16 = 4662,
        nickname: String = "MacMule",
        protocolVersion: UInt32 = ED2KLoginRequest.defaultProtocolVersion,
        flags: UInt32 = ED2KLoginRequest.defaultCompressionFlags,
        muleVersion: UInt32 = ED2KLoginRequest.defaultMuleVersion
    ) throws {
        try self.init(
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            tags: [
                ED2KTag(name: 0x01, value: .string(nickname)),
                ED2KTag(name: 0x11, value: .uint32(protocolVersion)),
                ED2KTag(name: 0x20, value: .uint32(flags)),
                ED2KTag(name: 0xFB, value: .uint32(muleVersion))
            ]
        )
    }

    public init(
        userHash: Data,
        clientID: UInt32 = 0,
        tcpPort: UInt16 = 4662,
        tags: [ED2KTag]
    ) throws {
        guard userHash.count == 16 else {
            throw ED2KLoginRequestError.invalidUserHashLength(userHash.count)
        }

        guard UInt32(exactly: tags.count) != nil else {
            throw ED2KLoginRequestError.tagCountTooLarge(tags.count)
        }

        self.userHash = userHash
        self.clientID = clientID
        self.tcpPort = tcpPort
        self.tags = tags
    }

    public func payload() throws -> Data {
        guard let tagCount = UInt32(exactly: tags.count) else {
            throw ED2KLoginRequestError.tagCountTooLarge(tags.count)
        }

        var data = Data()
        data.append(userHash)
        data.appendLittleEndian(clientID)
        data.appendLittleEndian(tcpPort)
        data.appendLittleEndian(tagCount)
        tags.forEach { data.append($0.encoded()) }
        return data
    }

    public func packet() throws -> ED2KPacket {
        try ED2KPacket(opcode: .loginRequest, payload: payload())
    }
}

public enum ED2KSearchRequestError: Error, Equatable, LocalizedError {
    case emptyQuery

    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "eD2k search query cannot be empty."
        }
    }
}

public enum ED2KSourceRequestError: Error, Equatable, LocalizedError {
    case invalidFileHashLength(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFileHashLength(let length):
            return "eD2k source lookup file hash must be 16 bytes, got \(length)."
        }
    }
}

public enum ED2KPeerHelloError: Error, Equatable, LocalizedError {
    case invalidUserHashLength(Int)
    case invalidHashLengthByte(UInt8)
    case tagCountTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidUserHashLength(let length):
            return "eD2k peer hello user hash must be 16 bytes, got \(length)."
        case .invalidHashLengthByte(let length):
            return "eD2k peer hello advertised unsupported hash length \(length)."
        case .tagCountTooLarge(let count):
            return "eD2k peer hello has too many tags: \(count)."
        }
    }
}

public enum ED2KPartRequestError: Error, Equatable, LocalizedError {
    case invalidFileHashLength(Int)
    case invalidRangeCount(Int)
    case invalidRange(start: UInt64, end: UInt64)

    public var errorDescription: String? {
        switch self {
        case .invalidFileHashLength(let length):
            return "eD2k part request file hash must be 16 bytes, got \(length)."
        case .invalidRangeCount(let count):
            return "eD2k part request must contain 1 to 3 ranges, got \(count)."
        case .invalidRange(let start, let end):
            return "eD2k part request range end \(end) must be greater than start \(start)."
        }
    }
}

public enum ED2KPartHashSetRequestError: Error, Equatable, LocalizedError {
    case invalidFileHashLength(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFileHashLength(let length):
            return "eD2k hashset request file hash must be 16 bytes, got \(length)."
        }
    }
}

public enum ED2KPeerFileCommandError: Error, Equatable, LocalizedError {
    case invalidFileHashLength(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFileHashLength(let length):
            return "eD2k peer file command hash must be 16 bytes, got \(length)."
        }
    }
}

public enum ED2KClientID {
    public static func isHighID(_ clientID: UInt32) -> Bool {
        clientID >= 0x01000000
    }

    public static func isLowID(_ clientID: UInt32) -> Bool {
        isHighID(clientID) == false
    }
}

public struct ED2KSearchRequest: Equatable, Sendable {
    public var query: String

    public init(query: String) throws {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw ED2KSearchRequestError.emptyQuery
        }

        self.query = normalized
    }

    public func payload() -> Data {
        let valueData = Data(query.utf8)
        var payload = Data([0x01])
        payload.appendLittleEndian(UInt16(valueData.count))
        payload.append(valueData)
        return payload
    }

    public func packet() -> ED2KPacket {
        ED2KPacket(opcode: .search, payload: payload())
    }
}

public struct ED2KSourceRequest: Equatable, Sendable {
    public var fileHash: Data
    public var fileSizeInBytes: UInt64

    public init(fileHash: Data, fileSizeInBytes: UInt64) throws {
        guard fileHash.count == 16 else {
            throw ED2KSourceRequestError.invalidFileHashLength(fileHash.count)
        }

        self.fileHash = fileHash
        self.fileSizeInBytes = fileSizeInBytes
    }

    public func payload() -> Data {
        var data = Data()
        data.append(fileHash)
        if fileSizeInBytes > UInt64(UInt32.max) {
            data.appendLittleEndian(UInt32(0))
            data.appendLittleEndian(fileSizeInBytes)
        } else {
            data.appendLittleEndian(UInt32(fileSizeInBytes))
        }
        return data
    }

    public func packet() -> ED2KPacket {
        ED2KPacket(opcode: .getSources, payload: payload())
    }
}

public struct ED2KServerCallbackRequest: Equatable, Sendable {
    public var clientID: UInt32

    public init(clientID: UInt32) {
        self.clientID = clientID
    }

    public func payload() -> Data {
        var data = Data()
        data.appendLittleEndian(clientID)
        return data
    }

    public func packet() -> ED2KPacket {
        ED2KPacket(opcode: .callbackRequest, payload: payload())
    }
}

public struct ED2KPartHashSetRequest: Equatable, Sendable {
    public var fileHash: Data

    public init(fileHash: Data) throws {
        guard fileHash.count == 16 else {
            throw ED2KPartHashSetRequestError.invalidFileHashLength(fileHash.count)
        }

        self.fileHash = fileHash
    }

    public func payload() -> Data {
        fileHash
    }

    public func packet() -> ED2KPacket {
        ED2KPacket(opcode: ED2KPeerPacketOpcode.hashSetRequest.rawValue, payload: payload())
    }
}

public struct ED2KPeerFileCommand: Equatable, Sendable {
    public var fileHash: Data

    public init(fileHash: Data) throws {
        guard fileHash.count == 16 else {
            throw ED2KPeerFileCommandError.invalidFileHashLength(fileHash.count)
        }

        self.fileHash = fileHash
    }

    public func packet(opcode: ED2KPeerPacketOpcode) -> ED2KPacket {
        ED2KPacket(opcode: opcode.rawValue, payload: fileHash)
    }
}

public struct ED2KPeerSourceExchangeRequest: Equatable, Sendable {
    public static let currentVersion: UInt8 = 4

    public var fileHash: Data
    public var version: UInt8

    public init(fileHash: Data, version: UInt8 = currentVersion) throws {
        guard fileHash.count == 16 else {
            throw ED2KPeerFileCommandError.invalidFileHashLength(fileHash.count)
        }
        guard version > 0 else {
            throw ED2KPacketError.invalidPayload("source exchange version must be greater than zero")
        }

        self.fileHash = fileHash
        self.version = version
    }

    public func payload() -> Data {
        var data = Data()
        data.append(version)
        data.appendLittleEndian(UInt16(0))
        data.append(fileHash)
        return data
    }

    public func packet() -> ED2KPacket {
        ED2KPacket(
            protocolByte: .emule,
            opcode: ED2KPeerPacketOpcode.requestSources2.rawValue,
            payload: payload()
        )
    }
}

public struct ED2KPeerEndpoint: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var port: UInt16

    public var address: String {
        "\(host):\(port)"
    }

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public struct ED2KPeerHello: Equatable, Sendable {
    public var userHash: Data
    public var clientID: UInt32
    public var tcpPort: UInt16
    public var tags: [ED2KTag]
    public var serverEndpoint: ED2KServerEndpoint

    public init(
        userHash: Data,
        clientID: UInt32 = 0,
        tcpPort: UInt16 = 4662,
        nickname: String = "MacMule",
        version: String = "MacMule/0.1",
        serverEndpoint: ED2KServerEndpoint = ED2KServerEndpoint(host: "0.0.0.0", port: 0)
    ) throws {
        try self.init(
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            tags: [
                ED2KTag(name: 0x01, value: .string(nickname)),
                ED2KTag(name: 0x11, value: .uint32(ED2KLoginRequest.defaultProtocolVersion)),
                ED2KTag(name: 0xF9, value: .uint32(0)),
                ED2KTag(name: 0xFA, value: .uint32(0x10000000)),
                ED2KTag(name: 0xFE, value: .uint32(0x00000010)),
                ED2KTag(name: 0xFB, value: .uint32(ED2KLoginRequest.defaultMuleVersion))
            ],
            serverEndpoint: serverEndpoint
        )
    }

    public init(
        userHash: Data,
        clientID: UInt32 = 0,
        tcpPort: UInt16 = 4662,
        tags: [ED2KTag],
        serverEndpoint: ED2KServerEndpoint = ED2KServerEndpoint(host: "0.0.0.0", port: 0)
    ) throws {
        guard userHash.count == 16 else {
            throw ED2KPeerHelloError.invalidUserHashLength(userHash.count)
        }

        guard UInt32(exactly: tags.count) != nil else {
            throw ED2KPeerHelloError.tagCountTooLarge(tags.count)
        }

        self.userHash = userHash
        self.clientID = clientID
        self.tcpPort = tcpPort
        self.tags = tags
        self.serverEndpoint = serverEndpoint
    }

    public func payload(includesHashLength: Bool = true) throws -> Data {
        guard let tagCount = UInt32(exactly: tags.count) else {
            throw ED2KPeerHelloError.tagCountTooLarge(tags.count)
        }

        var data = Data()
        if includesHashLength {
            data.append(0x10)
        }
        data.append(userHash)
        data.appendLittleEndian(clientID)
        data.appendLittleEndian(tcpPort)
        data.appendLittleEndian(tagCount)
        tags.forEach { data.append($0.encoded()) }
        data.append(contentsOf: serverEndpoint.host.octetsForED2KIPv4())
        data.appendLittleEndian(serverEndpoint.port)
        return data
    }

    public func packet(opcode: ED2KPeerPacketOpcode = .hello) throws -> ED2KPacket {
        try ED2KPacket(
            opcode: opcode.rawValue,
            payload: payload(includesHashLength: opcode == .hello)
        )
    }
}

public struct ED2KPartRange: Equatable, Sendable {
    public var startOffset: UInt64
    public var endOffset: UInt64

    public init(startOffset: UInt64, endOffset: UInt64) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct ED2KPartRequest: Equatable, Sendable {
    public var fileHash: Data
    public var ranges: [ED2KPartRange]

    public init(fileHash: Data, ranges: [ED2KPartRange]) throws {
        guard fileHash.count == 16 else {
            throw ED2KPartRequestError.invalidFileHashLength(fileHash.count)
        }
        guard (1...3).contains(ranges.count) else {
            throw ED2KPartRequestError.invalidRangeCount(ranges.count)
        }
        for range in ranges where range.endOffset <= range.startOffset {
            throw ED2KPartRequestError.invalidRange(start: range.startOffset, end: range.endOffset)
        }

        self.fileHash = fileHash
        self.ranges = ranges
    }

    public func payload() -> Data {
        var data = Data()
        data.append(fileHash)

        let paddedRanges = ranges + Array(repeating: ED2KPartRange(startOffset: 0, endOffset: 0), count: max(0, 3 - ranges.count))
        if uses64BitOffsets {
            for range in paddedRanges.prefix(3) {
                data.appendLittleEndian(range.startOffset)
            }
            for range in paddedRanges.prefix(3) {
                data.appendLittleEndian(range.endOffset)
            }
        } else {
            for range in paddedRanges.prefix(3) {
                data.appendLittleEndian(UInt32(range.startOffset))
            }
            for range in paddedRanges.prefix(3) {
                data.appendLittleEndian(UInt32(range.endOffset))
            }
        }

        return data
    }

    public var uses64BitOffsets: Bool {
        ranges.contains {
            $0.startOffset > UInt64(UInt32.max) || $0.endOffset > UInt64(UInt32.max)
        }
    }

    public func packet() -> ED2KPacket {
        if uses64BitOffsets {
            return ED2KPacket(
                protocolByte: .emule,
                opcode: ED2KPeerPacketOpcode.requestPartsI64.rawValue,
                payload: payload()
            )
        }

        return ED2KPacket(opcode: ED2KPeerPacketOpcode.requestParts.rawValue, payload: payload())
    }
}

public struct ED2KSendingPart: Equatable, Sendable {
    public var fileHash: Data
    public var startOffset: UInt64
    public var endOffset: UInt64
    public var block: Data

    public init(fileHash: Data, startOffset: UInt64, endOffset: UInt64, block: Data) {
        self.fileHash = fileHash
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.block = block
    }
}

public struct ED2KPartHashSet: Equatable, Sendable {
    public var fileHash: Data
    public var partHashes: [Data]

    public init(fileHash: Data, partHashes: [Data]) {
        self.fileHash = fileHash
        self.partHashes = partHashes
    }
}

public struct ED2KServerEndpoint: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var port: UInt16

    public var address: String {
        "\(host):\(port)"
    }

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public struct ED2KServerMessage: Equatable, Sendable {
    public var rawText: String
    public var lines: [String]

    public init(rawText: String) {
        self.rawText = rawText
        lines = rawText
            .components(separatedBy: .newlines)
            .filter { $0.isEmpty == false }
    }
}

public struct ED2KIDChange: Equatable, Sendable {
    public var clientID: UInt32
    public var tcpFlags: UInt32?
    public var auxiliaryTCPPort: UInt32?
    public var serverReportedIP: UInt32?
    public var obfuscationTCPPort: UInt32?

    public var highID: Bool {
        ED2KClientID.isHighID(clientID)
    }

    public init(
        clientID: UInt32,
        tcpFlags: UInt32? = nil,
        auxiliaryTCPPort: UInt32? = nil,
        serverReportedIP: UInt32? = nil,
        obfuscationTCPPort: UInt32? = nil
    ) {
        self.clientID = clientID
        self.tcpFlags = tcpFlags
        self.auxiliaryTCPPort = auxiliaryTCPPort
        self.serverReportedIP = serverReportedIP
        self.obfuscationTCPPort = obfuscationTCPPort
    }
}

public struct ED2KServerStatus: Equatable, Sendable {
    public var users: UInt32
    public var files: UInt32

    public init(users: UInt32, files: UInt32) {
        self.users = users
        self.files = files
    }
}

public struct ED2KServerIdentity: Equatable, Sendable {
    public var hash: Data
    public var endpoint: ED2KServerEndpoint

    public init(hash: Data, endpoint: ED2KServerEndpoint) {
        self.hash = hash
        self.endpoint = endpoint
    }
}

public struct ED2KSearchResult: Equatable, Sendable {
    public var fileHash: Data
    public var clientID: UInt32
    public var clientPort: UInt16
    public var tags: [ED2KTag]

    public init(fileHash: Data, clientID: UInt32, clientPort: UInt16, tags: [ED2KTag]) {
        self.fileHash = fileHash
        self.clientID = clientID
        self.clientPort = clientPort
        self.tags = tags
    }

    public func stringTag(named name: UInt8) -> String? {
        tags.first(where: { $0.name == name })?.value.stringValue
    }

    public func integerTag(named name: UInt8) -> UInt64? {
        tags.first(where: { $0.name == name })?.value.uint64Value
    }
}

public struct ED2KFoundSource: Equatable, Hashable, Sendable {
    public var clientID: UInt32
    public var clientPort: UInt16

    public init(clientID: UInt32, clientPort: UInt16) {
        self.clientID = clientID
        self.clientPort = clientPort
    }
}

public struct ED2KFoundSources: Equatable, Sendable {
    public var fileHash: Data
    public var sources: [ED2KFoundSource]

    public init(fileHash: Data, sources: [ED2KFoundSource]) {
        self.fileHash = fileHash
        self.sources = sources
    }
}

public struct ED2KPeerSourceExchangeSource: Equatable, Sendable {
    public var clientID: UInt32
    public var clientPort: UInt16
    public var serverEndpoint: ED2KServerEndpoint?
    public var userHash: Data?
    public var cryptOptions: UInt8?

    public init(
        clientID: UInt32,
        clientPort: UInt16,
        serverEndpoint: ED2KServerEndpoint?,
        userHash: Data? = nil,
        cryptOptions: UInt8? = nil
    ) {
        self.clientID = clientID
        self.clientPort = clientPort
        self.serverEndpoint = serverEndpoint
        self.userHash = userHash
        self.cryptOptions = cryptOptions
    }
}

public struct ED2KPeerSourceExchangeAnswer: Equatable, Sendable {
    public var version: UInt8
    public var fileHash: Data
    public var sources: [ED2KPeerSourceExchangeSource]

    public init(version: UInt8, fileHash: Data, sources: [ED2KPeerSourceExchangeSource]) {
        self.version = version
        self.fileHash = fileHash
        self.sources = sources
    }
}

public enum ED2KSearchTagName {
    public static let fileName: UInt8 = 0x01
    public static let fileSize: UInt8 = 0x02
    public static let sources: UInt8 = 0x15
    public static let completeSources: UInt8 = 0x30
}

public enum ED2KTagDecoder {
    static func decodeTagList(
        _ reader: inout ED2KBinaryReader,
        count: Int
    ) throws -> [ED2KTag] {
        var tags: [ED2KTag] = []
        tags.reserveCapacity(count)

        for _ in 0..<count {
            tags.append(try decodeTag(&reader))
        }

        return tags
    }

    static func decodeTag(_ reader: inout ED2KBinaryReader) throws -> ED2KTag {
        var type = try reader.readUInt8()
        let name: UInt8

        if type & 0x80 != 0 {
            type &= 0x7F
            name = try reader.readUInt8()
        } else {
            let nameLength = try Int(reader.readUInt16LittleEndian())
            if nameLength == 1 {
                name = try reader.readUInt8()
            } else {
                let nameData = try reader.readData(count: nameLength)
                name = mappedNumericName(for: nameData) ?? 0x00
            }
        }

        switch type {
        case 0x01:
            _ = try reader.readData(count: 16)
            return ED2KTag(name: name, value: .uint32(0))
        case 0x02:
            let length = try Int(reader.readUInt16LittleEndian())
            let bytes = try reader.readData(count: length)
            let value = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? String(decoding: bytes, as: UTF8.self)
            return ED2KTag(name: name, value: .string(value))
        case 0x03:
            return ED2KTag(name: name, value: .uint32(try reader.readUInt32LittleEndian()))
        case 0x08:
            return ED2KTag(name: name, value: .uint16(try reader.readUInt16LittleEndian()))
        case 0x09:
            return ED2KTag(name: name, value: .uint8(try reader.readUInt8()))
        case 0x0B:
            return ED2KTag(name: name, value: .uint64(try reader.readUInt64LittleEndian()))
        case 0x04:
            _ = try reader.readData(count: 4)
            return ED2KTag(name: name, value: .uint32(0))
        case 0x05:
            _ = try reader.readUInt8()
            return ED2KTag(name: name, value: .uint8(0))
        case 0x06:
            let bitCount = try Int(reader.readUInt16LittleEndian())
            _ = try reader.readData(count: bitCount / 8 + 1)
            return ED2KTag(name: name, value: .uint32(0))
        case 0x07:
            let length = try Int(reader.readUInt32LittleEndian())
            _ = try reader.readData(count: length)
            return ED2KTag(name: name, value: .uint32(0))
        case 0x11...0x20:
            let length = Int(type - 0x11 + 1)
            let bytes = try reader.readData(count: length)
            let value = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? String(decoding: bytes, as: UTF8.self)
            return ED2KTag(name: name, value: .string(value))
        default:
            throw ED2KPacketError.invalidPayload("unsupported tag value type 0x\(String(format: "%02X", type))")
        }
    }

    private static func mappedNumericName(for data: Data) -> UInt8? {
        let value = (String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self))
            .lowercased()

        switch value {
        case "name", "filename", "file", "fname", "nombre":
            return ED2KSearchTagName.fileName
        case "size", "filesize":
            return ED2KSearchTagName.fileSize
        case "sources":
            return ED2KSearchTagName.sources
        case "complete", "completesources":
            return ED2KSearchTagName.completeSources
        default:
            return nil
        }
    }
}

public enum ED2KServerMessageDecoder {
    public static func decodeServerMessagePayload(_ payload: Data) throws -> ED2KServerMessage {
        var reader = ED2KBinaryReader(data: payload)
        let length = try Int(reader.readUInt16LittleEndian())
        guard length <= payload.count - reader.offset else {
            let prefix = payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            throw ED2KPacketError.invalidPayload(
                "server message declared \(length) bytes but only \(payload.count - reader.offset) remain; prefix \(prefix)"
            )
        }
        let bytes = try reader.readData(count: length)

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("server message has trailing bytes")
        }

        let text = String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .isoLatin1)
            ?? String(decoding: bytes, as: UTF8.self)
        return ED2KServerMessage(rawText: text)
    }
}

public enum ED2KServerStatusDecoder {
    public static func decodeServerStatusPayload(_ payload: Data) throws -> ED2KServerStatus {
        var reader = ED2KBinaryReader(data: payload)
        let users = try reader.readUInt32LittleEndian()
        let files = try reader.readUInt32LittleEndian()
        return ED2KServerStatus(users: users, files: files)
    }
}

public enum ED2KIDChangeDecoder {
    public static func decodeIDChangePayload(_ payload: Data) throws -> ED2KIDChange {
        var reader = ED2KBinaryReader(data: payload)
        let clientID = try reader.readUInt32LittleEndian()
        let tcpFlags = try readOptionalUInt32(&reader)
        let auxiliaryTCPPort = try readOptionalUInt32(&reader)
        let serverReportedIP = try readOptionalUInt32(&reader)
        let obfuscationTCPPort = try readOptionalUInt32(&reader)

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("id change payload has trailing bytes")
        }

        return ED2KIDChange(
            clientID: clientID,
            tcpFlags: tcpFlags,
            auxiliaryTCPPort: auxiliaryTCPPort,
            serverReportedIP: serverReportedIP,
            obfuscationTCPPort: obfuscationTCPPort
        )
    }

    private static func readOptionalUInt32(_ reader: inout ED2KBinaryReader) throws -> UInt32? {
        guard reader.isAtEnd == false else {
            return nil
        }

        return try reader.readUInt32LittleEndian()
    }
}

public enum ED2KPeerHelloDecoder {
    public static func decodePeerHelloPayload(_ payload: Data, includesHashLength: Bool = true) throws -> ED2KPeerHello {
        var reader = ED2KBinaryReader(data: payload)
        if includesHashLength {
            let hashLength = try reader.readUInt8()
            guard hashLength == 16 else {
                throw ED2KPeerHelloError.invalidHashLengthByte(hashLength)
            }
        }

        let userHash = try reader.readData(count: 16)
        let clientID = try reader.readUInt32LittleEndian()
        let tcpPort = try reader.readUInt16LittleEndian()
        let tagCount = try Int(reader.readUInt32LittleEndian())
        let tags = try ED2KTagDecoder.decodeTagList(&reader, count: tagCount)
        let hostOctets = try reader.readBytes(count: 4)
        let serverPort = try reader.readUInt16LittleEndian()

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("peer hello payload has trailing bytes")
        }

        return try ED2KPeerHello(
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            tags: tags,
            serverEndpoint: ED2KServerEndpoint(
                host: hostOctets.map(String.init).joined(separator: "."),
                port: serverPort
            )
        )
    }
}

public enum ED2KServerIdentityDecoder {
    public static func decodeServerIdentPayload(_ payload: Data) throws -> ED2KServerIdentity {
        var reader = ED2KBinaryReader(data: payload)
        let hash = try reader.readData(count: 16)
        let octets = try reader.readBytes(count: 4)
        let remainingBytes = payload.count - reader.offset
        let port: UInt16

        switch remainingBytes {
        case 2:
            port = try reader.readUInt16LittleEndian()
        case 4:
            let rawPort = try reader.readUInt32LittleEndian()
            guard let parsedPort = UInt16(exactly: rawPort) else {
                throw ED2KPacketError.invalidPayload("server ident port exceeds UInt16")
            }
            port = parsedPort
        default:
            throw ED2KPacketError.invalidPayload("server ident expected 2 or 4 port bytes")
        }

        let host = octets.map(String.init).joined(separator: ".")
        return ED2KServerIdentity(
            hash: hash,
            endpoint: ED2KServerEndpoint(host: host, port: port)
        )
    }
}

public enum ED2KServerListDecoder {
    public static func decodeServerListPayload(_ payload: Data) throws -> [ED2KServerEndpoint] {
        var reader = ED2KBinaryReader(data: payload)
        let count = try Int(reader.readUInt8())
        var servers: [ED2KServerEndpoint] = []

        for _ in 0..<count {
            let octets = try reader.readBytes(count: 4)
            let port = try reader.readUInt16LittleEndian()
            let host = octets.map(String.init).joined(separator: ".")
            servers.append(ED2KServerEndpoint(host: host, port: port))
        }

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("server list has trailing bytes")
        }

        return servers
    }
}

public enum ED2KSearchResultDecoder {
    public static func decodeSearchResultPayload(_ payload: Data) throws -> [ED2KSearchResult] {
        var reader = ED2KBinaryReader(data: payload)
        let resultCount = try Int(reader.readUInt32LittleEndian())
        return try decodeSearchResults(&reader, count: resultCount)
    }

    static func decodeSearchResults(
        _ reader: inout ED2KBinaryReader,
        count: Int
    ) throws -> [ED2KSearchResult] {
        var results: [ED2KSearchResult] = []
        results.reserveCapacity(count)

        for _ in 0..<count {
            let fileHash = try reader.readData(count: 16)
            let clientID = try reader.readUInt32LittleEndian()
            let clientPort = try reader.readUInt16LittleEndian()
            let tagCount = try Int(reader.readUInt32LittleEndian())
            let tags = try ED2KTagDecoder.decodeTagList(&reader, count: tagCount)
            results.append(
                ED2KSearchResult(
                    fileHash: fileHash,
                    clientID: clientID,
                    clientPort: clientPort,
                    tags: tags
                )
            )
        }

        if reader.isAtEnd == false {
            let remainingByteCount = reader.remainingByteCount
            if remainingByteCount == 1 {
                let moreResultsFlag = try reader.readUInt8()
                guard moreResultsFlag == 0 || moreResultsFlag == 1 else {
                    throw ED2KPacketError.invalidPayload("search result has invalid more-results flag 0x\(String(format: "%02X", moreResultsFlag))")
                }
            } else {
                throw ED2KPacketError.invalidPayload("search result has trailing bytes")
            }
        }

        return results
    }
}

public enum ED2KFoundSourcesDecoder {
    public static func decodeFoundSourcesPayload(_ payload: Data) throws -> ED2KFoundSources {
        var reader = ED2KBinaryReader(data: payload)
        let fileHash = try reader.readData(count: 16)
        let sourceCount = try Int(reader.readUInt8())
        var sources: [ED2KFoundSource] = []
        sources.reserveCapacity(sourceCount)

        for _ in 0..<sourceCount {
            sources.append(
                ED2KFoundSource(
                    clientID: try reader.readUInt32LittleEndian(),
                    clientPort: try reader.readUInt16LittleEndian()
                )
            )
        }

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("found sources payload has trailing bytes")
        }

        return ED2KFoundSources(fileHash: fileHash, sources: sources)
    }

    public static func decodeObfuscatedFoundSourcesPayload(_ payload: Data) throws -> ED2KFoundSources {
        var reader = ED2KBinaryReader(data: payload)
        let fileHash = try reader.readData(count: 16)
        let sourceCount = try Int(reader.readUInt8())
        var sources: [ED2KFoundSource] = []
        sources.reserveCapacity(sourceCount)

        for _ in 0..<sourceCount {
            let clientID = try reader.readUInt32LittleEndian()
            let clientPort = try reader.readUInt16LittleEndian()
            let obfuscationOptions = try reader.readUInt8()
            if obfuscationOptions & 0x80 != 0 {
                _ = try reader.readData(count: 16)
            }
            sources.append(ED2KFoundSource(clientID: clientID, clientPort: clientPort))
        }

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("obfuscated found sources payload has trailing bytes")
        }

        return ED2KFoundSources(fileHash: fileHash, sources: sources)
    }
}

public enum ED2KPeerSourceExchangeDecoder {
    public static func decodeAnswerSourcesPayload(
        _ payload: Data,
        isSourceExchange2: Bool
    ) throws -> ED2KPeerSourceExchangeAnswer {
        var reader = ED2KBinaryReader(data: payload)
        let version = isSourceExchange2 ? try reader.readUInt8() : UInt8(1)

        guard (1...4).contains(version) else {
            throw ED2KPacketError.invalidPayload("unsupported source exchange version \(version)")
        }

        let fileHash = try reader.readData(count: 16)
        let sourceCount = try Int(reader.readUInt16LittleEndian())
        let entrySize = 4 + 2 + 4 + 2
            + (version >= 2 ? 16 : 0)
            + (version >= 4 ? 1 : 0)

        guard reader.remainingByteCount == sourceCount * entrySize else {
            throw ED2KPacketError.invalidPayload("source exchange answer has invalid source data size")
        }

        var sources: [ED2KPeerSourceExchangeSource] = []
        sources.reserveCapacity(sourceCount)

        for _ in 0..<sourceCount {
            let clientID = try reader.readUInt32LittleEndian()
            let clientPort = try reader.readUInt16LittleEndian()
            let serverIP = try reader.readUInt32LittleEndian()
            let serverPort = try reader.readUInt16LittleEndian()
            let userHash = version >= 2 ? try reader.readData(count: 16) : nil
            let cryptOptions = version >= 4 ? try reader.readUInt8() : nil

            sources.append(
                ED2KPeerSourceExchangeSource(
                    clientID: clientID,
                    clientPort: clientPort,
                    serverEndpoint: serverEndpoint(ip: serverIP, port: serverPort),
                    userHash: userHash,
                    cryptOptions: cryptOptions
                )
            )
        }

        return ED2KPeerSourceExchangeAnswer(version: version, fileHash: fileHash, sources: sources)
    }

    private static func serverEndpoint(ip: UInt32, port: UInt16) -> ED2KServerEndpoint? {
        guard ip != 0, port != 0 else {
            return nil
        }

        let octets = [
            UInt8(ip & 0x000000FF),
            UInt8((ip >> 8) & 0x000000FF),
            UInt8((ip >> 16) & 0x000000FF),
            UInt8((ip >> 24) & 0x000000FF)
        ]

        return ED2KServerEndpoint(host: octets.map(String.init).joined(separator: "."), port: port)
    }
}

public enum ED2KPartRequestDecoder {
    public static func decodePartRequestPayload(_ payload: Data, uses64BitOffsets: Bool = false) throws -> ED2KPartRequest {
        var reader = ED2KBinaryReader(data: payload)
        let fileHash = try reader.readData(count: 16)

        var starts: [UInt64] = []
        var ends: [UInt64] = []
        starts.reserveCapacity(3)
        ends.reserveCapacity(3)

        for _ in 0..<3 {
            starts.append(try readOffset(&reader, uses64BitOffsets: uses64BitOffsets))
        }

        for _ in 0..<3 {
            ends.append(try readOffset(&reader, uses64BitOffsets: uses64BitOffsets))
        }

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("part request payload has trailing bytes")
        }

        var ranges: [ED2KPartRange] = []
        for index in 0..<3 {
            let start = starts[index]
            let end = ends[index]

            if start == 0 && end == 0 {
                continue
            }

            ranges.append(ED2KPartRange(startOffset: start, endOffset: end))
        }

        return try ED2KPartRequest(fileHash: fileHash, ranges: ranges)
    }

    private static func readOffset(_ reader: inout ED2KBinaryReader, uses64BitOffsets: Bool) throws -> UInt64 {
        if uses64BitOffsets {
            return try reader.readUInt64LittleEndian()
        }

        return UInt64(try reader.readUInt32LittleEndian())
    }
}

public enum ED2KPartHashSetDecoder {
    public static func decodePartHashSetPayload(_ payload: Data) throws -> ED2KPartHashSet {
        var reader = ED2KBinaryReader(data: payload)
        let fileHash = try reader.readData(count: 16)
        let partCount = try Int(reader.readUInt16LittleEndian())
        var partHashes: [Data] = []
        partHashes.reserveCapacity(partCount)

        for _ in 0..<partCount {
            partHashes.append(try reader.readData(count: 16))
        }

        guard reader.isAtEnd else {
            throw ED2KPacketError.invalidPayload("hashset answer payload has trailing bytes")
        }

        return ED2KPartHashSet(fileHash: fileHash, partHashes: partHashes)
    }
}

public enum ED2KSendingPartDecoder {
    public static func decodeSendingPartPayload(
        _ payload: Data,
        uses64BitOffsets: Bool = false,
        isCompressed: Bool = false
    ) throws -> ED2KSendingPart {
        var reader = ED2KBinaryReader(data: payload)
        let fileHash = try reader.readData(count: 16)
        let startOffset = try readOffset(&reader, uses64BitOffsets: uses64BitOffsets)
        let endOffset: UInt64
        let block: Data

        if isCompressed {
            _ = try reader.readUInt32LittleEndian()
            let compressedBlock = try reader.readData(count: payload.count - reader.offset)
            block = try ED2KPackedPacketDecoder.inflateZlib(compressedBlock)
            endOffset = startOffset + UInt64(block.count)
        } else {
            endOffset = try readOffset(&reader, uses64BitOffsets: uses64BitOffsets)
            block = try reader.readData(count: payload.count - reader.offset)
        }

        guard endOffset > startOffset else {
            throw ED2KPacketError.invalidPayload("sending part range end must be greater than start")
        }

        guard let expectedLength = Int(exactly: endOffset - startOffset) else {
            throw ED2KPacketError.invalidPayload("sending part block length exceeds platform limits")
        }

        guard block.count == expectedLength else {
            throw ED2KPacketError.invalidPayload("sending part block length \(block.count) does not match advertised range \(expectedLength)")
        }

        return ED2KSendingPart(
            fileHash: fileHash,
            startOffset: startOffset,
            endOffset: endOffset,
            block: block
        )
    }

    private static func readOffset(_ reader: inout ED2KBinaryReader, uses64BitOffsets: Bool) throws -> UInt64 {
        if uses64BitOffsets {
            return try reader.readUInt64LittleEndian()
        }

        return UInt64(try reader.readUInt32LittleEndian())
    }
}

struct ED2KBinaryReader {
    var data: Data
    var offset = 0

    var isAtEnd: Bool {
        offset == data.count
    }

    var remainingByteCount: Int {
        data.count - offset
    }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(count: 1)
        return bytes[0]
    }

    mutating func readUInt16LittleEndian() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    mutating func readUInt32LittleEndian() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    mutating func readUInt64LittleEndian() throws -> UInt64 {
        let bytes = try readBytes(count: 8)
        return UInt64(bytes[0])
            | (UInt64(bytes[1]) << 8)
            | (UInt64(bytes[2]) << 16)
            | (UInt64(bytes[3]) << 24)
            | (UInt64(bytes[4]) << 32)
            | (UInt64(bytes[5]) << 40)
            | (UInt64(bytes[6]) << 48)
            | (UInt64(bytes[7]) << 56)
    }

    mutating func readData(count: Int) throws -> Data {
        guard offset + count <= data.count else {
            throw ED2KPacketError.invalidPayload("expected \(count) more bytes")
        }

        let startIndex = data.index(data.startIndex, offsetBy: offset)
        let endIndex = data.index(startIndex, offsetBy: count)
        offset += count
        return Data(data[startIndex..<endIndex])
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else {
            throw ED2KPacketError.invalidPayload("expected \(count) more bytes")
        }

        let startIndex = data.index(data.startIndex, offsetBy: offset)
        let endIndex = data.index(startIndex, offsetBy: count)
        offset += count
        return Array(data[startIndex..<endIndex])
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        append(UInt8(value & 0x00000000000000FF))
        append(UInt8((value >> 8) & 0x00000000000000FF))
        append(UInt8((value >> 16) & 0x00000000000000FF))
        append(UInt8((value >> 24) & 0x00000000000000FF))
        append(UInt8((value >> 32) & 0x00000000000000FF))
        append(UInt8((value >> 40) & 0x00000000000000FF))
        append(UInt8((value >> 48) & 0x00000000000000FF))
        append(UInt8((value >> 56) & 0x00000000000000FF))
    }

    func readUInt32LittleEndian(at offset: Int) -> UInt32 {
        let start = index(startIndex, offsetBy: offset)
        let byte0 = UInt32(self[start])
        let byte1 = UInt32(self[index(after: start)]) << 8
        let byte2 = UInt32(self[index(start, offsetBy: 2)]) << 16
        let byte3 = UInt32(self[index(start, offsetBy: 3)]) << 24
        return byte0 | byte1 | byte2 | byte3
    }
}

private extension String {
    func octetsForED2KIPv4() -> [UInt8] {
        let components = split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else {
            return [0, 0, 0, 0]
        }

        let octets = components.compactMap { UInt8($0) }
        guard octets.count == 4 else {
            return [0, 0, 0, 0]
        }

        return octets
    }
}
