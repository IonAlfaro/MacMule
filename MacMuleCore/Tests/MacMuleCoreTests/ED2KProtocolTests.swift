import Compression
import XCTest
@testable import MacMuleCore

final class ED2KProtocolTests: XCTestCase {
    func testPacketEncodingUsesLittleEndianSizeIncludingOpcode() {
        let packet = ED2KPacket(
            opcode: .loginRequest,
            payload: Data([0xAA, 0xBB])
        )

        XCTAssertEqual(
            Array(packet.encoded()),
            [0xE3, 0x03, 0x00, 0x00, 0x00, 0x01, 0xAA, 0xBB]
        )
    }

    func testPacketDecodeRoundTripsEncodedPacket() throws {
        let packet = ED2KPacket(
            protocolByte: .emule,
            opcode: 0x55,
            payload: Data([0x01, 0x02, 0x03])
        )

        XCTAssertEqual(try ED2KPacket.decode(packet.encoded()), packet)
    }

    func testPacketDecodeInflatesPackedPacket() throws {
        let payload = Data([0x05, 0x00]) + Data("hello".utf8)
        let compressedPayload = try zlibCompressed(payload)
        var encoded = Data()
        encoded.append(0xD4)
        encoded.appendUInt32LittleEndian(UInt32(compressedPayload.count + 1))
        encoded.append(ED2KPacketOpcode.serverMessage.rawValue)
        encoded.append(compressedPayload)

        XCTAssertEqual(
            try ED2KPacket.decode(encoded),
            ED2KPacket(opcode: .serverMessage, payload: payload)
        )
    }

    func testPacketDecodeInflatesRawDeflatePackedPacket() throws {
        let payload = Data([0x05, 0x00]) + Data("hello".utf8)
        let compressedPayload = Data([0x63, 0x65, 0xC8, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00])
        var encoded = Data()
        encoded.append(0xD4)
        encoded.appendUInt32LittleEndian(UInt32(compressedPayload.count + 1))
        encoded.append(ED2KPacketOpcode.serverMessage.rawValue)
        encoded.append(compressedPayload)

        XCTAssertEqual(
            try ED2KPacket.decode(encoded),
            ED2KPacket(opcode: .serverMessage, payload: payload)
        )
    }

    func testPacketDecodeRejectsSizeMismatch() {
        XCTAssertThrowsError(
            try ED2KPacket.decode(Data([0xE3, 0x03, 0x00, 0x00, 0x00, 0x01]))
        ) { error in
            XCTAssertEqual(error as? ED2KPacketError, .invalidSize(expected: 8, actual: 6))
        }
    }

    func testStreamDecoderBuffersPartialPackets() throws {
        let packet = ED2KPacket(opcode: .serverMessage, payload: Data([0x01, 0x02, 0x03]))
        let encoded = packet.encoded()
        var decoder = ED2KPacketStreamDecoder()

        XCTAssertEqual(try decoder.append(Data(encoded.prefix(4))), [])
        XCTAssertEqual(decoder.bufferedByteCount, 4)
        XCTAssertEqual(try decoder.append(Data(encoded.dropFirst(4))), [packet])
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testStreamDecoderInflatesPackedPacket() throws {
        let payload = Data([0x02, 0x00]) + Data("ok".utf8)
        let compressedPayload = try zlibCompressed(payload)
        var encoded = Data()
        encoded.append(0xD4)
        encoded.appendUInt32LittleEndian(UInt32(compressedPayload.count + 1))
        encoded.append(ED2KPacketOpcode.serverMessage.rawValue)
        encoded.append(compressedPayload)
        var decoder = ED2KPacketStreamDecoder()

        XCTAssertEqual(
            try decoder.append(encoded),
            [ED2KPacket(opcode: .serverMessage, payload: payload)]
        )
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testStreamDecoderReturnsMultiplePacketsAndKeepsTrailingBytes() throws {
        let firstPacket = ED2KPacket(opcode: .serverMessage, payload: Data([0x01]))
        let secondPacket = ED2KPacket(opcode: .serverList, payload: Data([0x00]))
        let secondPrefix = Data(secondPacket.encoded().prefix(5))
        var decoder = ED2KPacketStreamDecoder()
        var bytes = Data()
        bytes.append(firstPacket.encoded())
        bytes.append(secondPacket.encoded())
        bytes.append(secondPrefix)

        XCTAssertEqual(try decoder.append(bytes), [firstPacket, secondPacket])
        XCTAssertEqual(decoder.bufferedByteCount, secondPrefix.count)
        XCTAssertEqual(try decoder.append(Data(secondPacket.encoded().dropFirst(5))), [secondPacket])
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testLoginRequestEncodesExpectedPayload() throws {
        let userHash = Data(0..<16)
        let login = try ED2KLoginRequest(
            userHash: userHash,
            tcpPort: 4662,
            nickname: "MacMule",
            protocolVersion: 60,
            flags: 1
        )

        let encoded = try login.packet().encoded()

        XCTAssertEqual(encoded[0], 0xE3)
        XCTAssertEqual(Array(encoded[1...4]), [0x40, 0x00, 0x00, 0x00])
        XCTAssertEqual(encoded[5], ED2KPacketOpcode.loginRequest.rawValue)
        XCTAssertEqual(Array(encoded[6..<22]), Array(0..<16))
        XCTAssertEqual(Array(encoded[22..<26]), [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(encoded[26..<28]), [0x36, 0x12])
        XCTAssertEqual(Array(encoded[28..<32]), [0x04, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(encoded[32..<45]), [0x02, 0x01, 0x00, 0x01, 0x07, 0x00] + Array("MacMule".utf8))
        XCTAssertEqual(Array(encoded[45..<53]), [0x03, 0x01, 0x00, 0x11, 0x3C, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(encoded[53..<61]), [0x03, 0x01, 0x00, 0x20, 0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(encoded[61..<69]), [0x03, 0x01, 0x00, 0xFB, 0x00, 0x20, 0x01, 0x00])
    }

    func testLoginRequestDefaultsAdvertiseEMuleCapabilities() throws {
        let login = try ED2KLoginRequest(
            userHash: Data(0..<16),
            tcpPort: 4662,
            nickname: "MacMule"
        )

        XCTAssertEqual(ED2KLoginRequest.legacyDefaultServerCapabilityFlags, 0x0119)
        XCTAssertEqual(ED2KLoginRequest.defaultCompressionFlags, 0x0719)
        XCTAssertEqual(ED2KLoginRequest.defaultMuleVersion, 0x00012000)
        XCTAssertEqual(login.tags.count, 4)
        XCTAssertEqual(login.tags[1], ED2KTag(name: 0x11, value: .uint32(ED2KLoginRequest.defaultProtocolVersion)))
        XCTAssertEqual(login.tags[2], ED2KTag(name: 0x20, value: .uint32(ED2KLoginRequest.defaultCompressionFlags)))
        XCTAssertEqual(login.tags[3], ED2KTag(name: 0xFB, value: .uint32(ED2KLoginRequest.defaultMuleVersion)))
    }

    func testLoginRequestRequiresSixteenByteUserHash() {
        XCTAssertThrowsError(try ED2KLoginRequest(userHash: Data([1, 2, 3]))) { error in
            XCTAssertEqual(error as? ED2KLoginRequestError, .invalidUserHashLength(3))
        }
    }

    func testSearchRequestEncodesSingleStringOperand() throws {
        let packet = try ED2KSearchRequest(query: "ubuntu iso").packet()
        let valueData = Data("ubuntu iso".utf8)
        let count = UInt16(valueData.count)
        var expectedPayload = Data([0x01])
        expectedPayload.append(contentsOf: [UInt8(count & 0xFF), UInt8((count >> 8) & 0xFF)])
        expectedPayload.append(valueData)

        XCTAssertEqual(packet.opcode, ED2KPacketOpcode.search.rawValue)
        XCTAssertEqual(Array(packet.payload), Array(expectedPayload))
    }

    func testSearchRequestForSingleWordMatchesEMuleStringParameterShape() throws {
        let packet = try ED2KSearchRequest(query: "ubuntu").packet()

        XCTAssertEqual(packet.opcode, ED2KPacketOpcode.search.rawValue)
        XCTAssertEqual(Array(packet.encoded()), [
            0xE3,
            0x0A, 0x00, 0x00, 0x00,
            ED2KPacketOpcode.search.rawValue,
            0x01,
            0x06, 0x00,
            0x75, 0x62, 0x75, 0x6E, 0x74, 0x75
        ])
    }

    func testSearchRequestRejectsEmptyQuery() {
        XCTAssertThrowsError(try ED2KSearchRequest(query: "   ")) { error in
            XCTAssertEqual(error as? ED2KSearchRequestError, .emptyQuery)
        }
    }

    func testSourceRequestEncodesFileHashPayload() throws {
        let hash = Data((0..<16).map(UInt8.init))
        let packet = try ED2KSourceRequest(fileHash: hash, fileSizeInBytes: 1_048_576).packet()

        XCTAssertEqual(packet.opcode, ED2KPacketOpcode.getSources.rawValue)
        XCTAssertEqual(packet.payload, hash + Data([0x00, 0x00, 0x10, 0x00]))
    }

    func testSourceRequestEncodesLargeFileSizeMarkerAndUInt64Size() throws {
        let hash = Data((0..<16).map(UInt8.init))
        let fileSize = UInt64(UInt32.max) + 1
        let packet = try ED2KSourceRequest(fileHash: hash, fileSizeInBytes: fileSize).packet()
        var expectedPayload = hash
        expectedPayload.appendUInt32LittleEndian(0)
        expectedPayload.appendUInt64LittleEndian(fileSize)

        XCTAssertEqual(packet.opcode, ED2KPacketOpcode.getSources.rawValue)
        XCTAssertEqual(packet.payload, expectedPayload)
    }

    func testPeerSourceExchangeRequestEncodesSX2Payload() throws {
        let hash = Data((0..<16).map(UInt8.init))
        let packet = try ED2KPeerSourceExchangeRequest(fileHash: hash).packet()

        XCTAssertEqual(packet.protocolByte, .emule)
        XCTAssertEqual(packet.opcode, ED2KPeerPacketOpcode.requestSources2.rawValue)
        XCTAssertEqual(packet.payload, Data([0x04, 0x00, 0x00]) + hash)
    }

    func testPeerSourceExchangeAnswerDecoderParsesSX2Sources() throws {
        var payload = Data([0x04])
        payload.append(Data((0..<16).map(UInt8.init)))
        payload.append(contentsOf: [0x01, 0x00])
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x08, 0x07, 0x06, 0x05])
        payload.append(contentsOf: [0x35, 0x12])
        payload.append(Data(repeating: 0xAB, count: 16))
        payload.append(0x03)

        let answer = try ED2KPeerSourceExchangeDecoder.decodeAnswerSourcesPayload(
            payload,
            isSourceExchange2: true
        )

        XCTAssertEqual(answer.version, 4)
        XCTAssertEqual(answer.fileHash, Data((0..<16).map(UInt8.init)))
        XCTAssertEqual(answer.sources, [
            ED2KPeerSourceExchangeSource(
                clientID: 0x01020304,
                clientPort: 4662,
                serverEndpoint: ED2KServerEndpoint(host: "8.7.6.5", port: 4661),
                userHash: Data(repeating: 0xAB, count: 16),
                cryptOptions: 0x03
            )
        ])
    }

    func testFoundSourcesDecoderParsesSourceList() throws {
        var payload = Data((0..<16).map(UInt8.init))
        payload.append(0x02)
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x08, 0x07, 0x06, 0x05])
        payload.append(contentsOf: [0x40, 0x12])

        let foundSources = try ED2KFoundSourcesDecoder.decodeFoundSourcesPayload(payload)

        XCTAssertEqual(foundSources.fileHash, Data((0..<16).map(UInt8.init)))
        XCTAssertEqual(foundSources.sources, [
            ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
            ED2KFoundSource(clientID: 0x05060708, clientPort: 4672)
        ])
    }

    func testObfuscatedFoundSourcesDecoderSkipsCryptMetadata() throws {
        var payload = Data((0..<16).map(UInt8.init))
        payload.append(0x02)
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(0x00)
        payload.append(contentsOf: [0x08, 0x07, 0x06, 0x05])
        payload.append(contentsOf: [0x40, 0x12])
        payload.append(0x80)
        payload.append(Data(repeating: 0xAB, count: 16))

        let foundSources = try ED2KFoundSourcesDecoder.decodeObfuscatedFoundSourcesPayload(payload)

        XCTAssertEqual(foundSources.fileHash, Data((0..<16).map(UInt8.init)))
        XCTAssertEqual(foundSources.sources, [
            ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
            ED2KFoundSource(clientID: 0x05060708, clientPort: 4672)
        ])
    }

    func testCallbackRequestedDecoderReadsEndpointAndSkipsTrailingMetadata() throws {
        var payload = Data([198, 51, 100, 24])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(0x01)
        payload.append(Data(repeating: 0xAB, count: 16))

        XCTAssertEqual(
            try ED2KCallbackRequestedDecoder.decodeCallbackRequestedPayload(payload),
            ED2KPeerEndpoint(host: "198.51.100.24", port: 4662)
        )
    }

    func testPeerHelloEncodesAndDecodesPayload() throws {
        let hello = try ED2KPeerHello(
            userHash: Data(0..<16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "Peer Mule",
            version: "PeerMule/1.0",
            serverEndpoint: ED2KServerEndpoint(host: "91.121.79.35", port: 4661)
        )

        let packet = try hello.packet(opcode: .hello)
        XCTAssertEqual(packet.opcode, ED2KPeerPacketOpcode.hello.rawValue)
        XCTAssertEqual(packet.payload.first, 0x10)
        XCTAssertEqual(Array(packet.payload[1..<17]), Array(0..<16))
        XCTAssertEqual(Array(packet.payload.suffix(6)), [0x5B, 0x79, 0x4F, 0x23, 0x35, 0x12])
        XCTAssertEqual(try ED2KPeerHelloDecoder.decodePeerHelloPayload(packet.payload), hello)
    }

    func testPeerHelloAnswerOmitsHashLengthByteLikeEMule() throws {
        let hello = try ED2KPeerHello(
            userHash: Data(0..<16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "Peer Mule",
            version: "PeerMule/1.0",
            serverEndpoint: ED2KServerEndpoint(host: "91.121.79.35", port: 4661)
        )

        let packet = try hello.packet(opcode: .helloAnswer)
        XCTAssertEqual(packet.opcode, ED2KPeerPacketOpcode.helloAnswer.rawValue)
        XCTAssertEqual(packet.payload.first, 0x00)
        XCTAssertEqual(Array(packet.payload.prefix(16)), Array(0..<16))
        XCTAssertEqual(Array(packet.payload.suffix(6)), [0x5B, 0x79, 0x4F, 0x23, 0x35, 0x12])
        XCTAssertEqual(
            try ED2KPeerHelloDecoder.decodePeerHelloPayload(packet.payload, includesHashLength: false),
            hello
        )
        XCTAssertThrowsError(try ED2KPeerHelloDecoder.decodePeerHelloPayload(packet.payload)) { error in
            XCTAssertEqual(error as? ED2KPeerHelloError, .invalidHashLengthByte(0))
        }
    }

    func testPartRequestEncodesAndDecodesPaddedRanges() throws {
        let request = try ED2KPartRequest(
            fileHash: Data(0..<16),
            ranges: [
                ED2KPartRange(startOffset: 0, endOffset: 1024),
                ED2KPartRange(startOffset: 4096, endOffset: 6144)
            ]
        )
        let packet = request.packet()

        XCTAssertEqual(packet.opcode, ED2KPeerPacketOpcode.requestParts.rawValue)
        XCTAssertEqual(packet.payload.count, 40)
        XCTAssertEqual(try ED2KPartRequestDecoder.decodePartRequestPayload(packet.payload), request)
    }

    func testPartRequestUsesI64ForLargeOffsets() throws {
        let start = UInt64(UInt32.max) + 1
        let request = try ED2KPartRequest(
            fileHash: Data(0..<16),
            ranges: [
                ED2KPartRange(startOffset: start, endOffset: start + 1024)
            ]
        )
        let packet = request.packet()

        XCTAssertEqual(packet.protocolByte, .emule)
        XCTAssertEqual(packet.opcode, ED2KPeerPacketOpcode.requestPartsI64.rawValue)
        XCTAssertEqual(packet.payload.count, 64)
        XCTAssertEqual(
            try ED2KPartRequestDecoder.decodePartRequestPayload(packet.payload, uses64BitOffsets: true),
            request
        )
    }

    func testPartHashSetRequestEncodesFileHashPayload() throws {
        let request = try ED2KPartHashSetRequest(fileHash: Data(0..<16))
        let packet = request.packet()

        XCTAssertEqual(packet.opcode, ED2KPeerPacketOpcode.hashSetRequest.rawValue)
        XCTAssertEqual(packet.payload, Data(0..<16))
    }

    func testPartHashSetDecoderParsesReplyPayload() throws {
        var payload = Data(0..<16)
        payload.append(contentsOf: [0x02, 0x00])
        payload.append(Data(repeating: 0x11, count: 16))
        payload.append(Data(repeating: 0x22, count: 16))

        XCTAssertEqual(
            try ED2KPartHashSetDecoder.decodePartHashSetPayload(payload),
            ED2KPartHashSet(
                fileHash: Data(0..<16),
                partHashes: [
                    Data(repeating: 0x11, count: 16),
                    Data(repeating: 0x22, count: 16)
                ]
            )
        )
    }

    func testSendingPartDecoderParsesPayload() throws {
        var payload = Data(0..<16)
        payload.append(contentsOf: [0x00, 0x10, 0x00, 0x00])
        payload.append(contentsOf: [0x04, 0x10, 0x00, 0x00])
        payload.append(Data(repeating: 0xAB, count: 4))

        XCTAssertEqual(
            try ED2KSendingPartDecoder.decodeSendingPartPayload(payload),
            ED2KSendingPart(
                fileHash: Data(0..<16),
                startOffset: 4096,
                endOffset: 4100,
                block: Data(repeating: 0xAB, count: 4)
            )
        )
    }

    func testSendingPartDecoderParsesI64Payload() throws {
        let start = UInt64(UInt32.max) + 4096
        var payload = Data(0..<16)
        payload.appendUInt64LittleEndian(start)
        payload.appendUInt64LittleEndian(start + 4)
        payload.append(Data(repeating: 0xCD, count: 4))

        XCTAssertEqual(
            try ED2KSendingPartDecoder.decodeSendingPartPayload(payload, uses64BitOffsets: true),
            ED2KSendingPart(
                fileHash: Data(0..<16),
                startOffset: start,
                endOffset: start + 4,
                block: Data(repeating: 0xCD, count: 4)
            )
        )
    }

    func testDecodesServerListPayload() throws {
        let payload = Data([
            0x02,
            0x7F, 0x00, 0x00, 0x01, 0x35, 0x12,
            0x5B, 0x79, 0x4F, 0x23, 0x36, 0x12
        ])

        XCTAssertEqual(
            try ED2KServerListDecoder.decodeServerListPayload(payload),
            [
                ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
                ED2KServerEndpoint(host: "91.121.79.35", port: 4662)
            ]
        )
    }

    func testDecodesSearchResultPayload() throws {
        var payload = Data([0x01, 0x00, 0x00, 0x00])
        payload.append(Data(0..<16))
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
        payload.append(ED2KTag(name: ED2KSearchTagName.fileName, value: .string("Ubuntu.iso")).encoded())
        payload.append(ED2KTag(name: ED2KSearchTagName.fileSize, value: .uint64(5_812_142_080)).encoded())

        let results = try ED2KSearchResultDecoder.decodeSearchResultPayload(payload)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].fileHash, Data(0..<16))
        XCTAssertEqual(results[0].clientID, 0x01020304)
        XCTAssertEqual(results[0].clientPort, 4662)
        XCTAssertEqual(results[0].stringTag(named: ED2KSearchTagName.fileName), "Ubuntu.iso")
        XCTAssertEqual(results[0].integerTag(named: ED2KSearchTagName.fileSize), 5_812_142_080)
    }

    func testDecodesSearchResultPayloadWithSpecialCompactTags() throws {
        var payload = Data([0x01, 0x00, 0x00, 0x00])
        payload.append(Data(0..<16))
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [0x82, ED2KSearchTagName.fileName, 0x08, 0x00])
        payload.append(Data("Live.iso".utf8))
        payload.append(contentsOf: [0x8B, ED2KSearchTagName.fileSize])
        payload.append(contentsOf: [0x00, 0x40, 0x6E, 0x5A, 0x01, 0x00, 0x00, 0x00])

        let results = try ED2KSearchResultDecoder.decodeSearchResultPayload(payload)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].stringTag(named: ED2KSearchTagName.fileName), "Live.iso")
        XCTAssertEqual(results[0].integerTag(named: ED2KSearchTagName.fileSize), 5_812_142_080)
    }

    func testDecodesSearchResultPayloadWithMoreResultsFlag() throws {
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        payload.append(0x01)

        XCTAssertEqual(try ED2KSearchResultDecoder.decodeSearchResultPayload(payload), [])
    }

    func testDecodesServerStatusPayload() throws {
        XCTAssertEqual(
            try ED2KServerStatusDecoder.decodeServerStatusPayload(Data([0x39, 0x30, 0x00, 0x00, 0xA0, 0x86, 0x01, 0x00])),
            ED2KServerStatus(users: 12_345, files: 100_000)
        )
    }

    func testDecodesServerMessagePayload() throws {
        var payload = Data()
        payload.append(0x1D)
        payload.append(0x00)
        payload.append(Data("server version 17.15\r\nwelcome".utf8))

        XCTAssertEqual(
            try ED2KServerMessageDecoder.decodeServerMessagePayload(payload),
            ED2KServerMessage(rawText: "server version 17.15\r\nwelcome")
        )
        XCTAssertEqual(
            try ED2KServerMessageDecoder.decodeServerMessagePayload(payload).lines,
            ["server version 17.15", "welcome"]
        )
    }

    func testDecodesServerIdentPayloadWithTwoBytePort() throws {
        let hash = Data(0..<16)
        var payload = Data()
        payload.append(hash)
        payload.append(contentsOf: [0x7F, 0x00, 0x00, 0x01])
        payload.append(contentsOf: [0x35, 0x12])

        XCTAssertEqual(
            try ED2KServerIdentityDecoder.decodeServerIdentPayload(payload),
            ED2KServerIdentity(
                hash: hash,
                endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
            )
        )
    }

    func testDecodesServerIdentPayloadWithFourBytePort() throws {
        let hash = Data(0..<16)
        var payload = Data()
        payload.append(hash)
        payload.append(contentsOf: [0x5B, 0x79, 0x4F, 0x23])
        payload.append(contentsOf: [0x36, 0x12, 0x00, 0x00])

        XCTAssertEqual(
            try ED2KServerIdentityDecoder.decodeServerIdentPayload(payload),
            ED2KServerIdentity(
                hash: hash,
                endpoint: ED2KServerEndpoint(host: "91.121.79.35", port: 4662)
            )
        )
    }
}

private enum ED2KProtocolTestError: Error {
    case compressionFailed
}

private func zlibCompressed(_ data: Data) throws -> Data {
    let capacity = max(data.count + 64, 256)
    var output = Data(count: capacity)
    let encodedSize = output.withUnsafeMutableBytes { outputBuffer -> Int in
        guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return 0
        }

        return data.withUnsafeBytes { inputBuffer -> Int in
            guard let inputBase = inputBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }

            return compression_encode_buffer(
                outputBase,
                capacity,
                inputBase,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
    }

    guard encodedSize > 0 else {
        throw ED2KProtocolTestError.compressionFailed
    }

    output.removeSubrange(encodedSize..<output.count)
    return output
}

private extension Data {
    mutating func appendUInt32LittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func appendUInt64LittleEndian(_ value: UInt64) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 32))
        append(UInt8(truncatingIfNeeded: value >> 40))
        append(UInt8(truncatingIfNeeded: value >> 48))
        append(UInt8(truncatingIfNeeded: value >> 56))
    }
}
