import XCTest
@testable import MacMuleCore

final class ED2KPeerSessionTests: XCTestCase {
    func testHelloEventsUseConfiguration() throws {
        let configuration = makeConfiguration()
        let session = ED2KPeerSession(configuration: configuration)

        XCTAssertEqual(
            try session.helloEvent(),
            .outgoingHello(try configuration.hello().packet(opcode: .hello))
        )
        XCTAssertEqual(
            try session.helloAnswerEvent(),
            .outgoingHelloAnswer(try configuration.hello().packet(opcode: .helloAnswer))
        )
    }

    func testReceiveBuffersPeerHelloAnswer() throws {
        var session = ED2KPeerSession(configuration: makeConfiguration())
        let hello = try ED2KPeerHello(
            userHash: Data(0..<16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "Peer Mule",
            version: "PeerMule/1.0",
            serverEndpoint: ED2KServerEndpoint(host: "91.121.79.35", port: 4661)
        )
        let packet = try hello.packet(opcode: .helloAnswer)
        let encoded = packet.encoded()

        XCTAssertEqual(try session.receive(Data(encoded.prefix(9))), [])
        XCTAssertEqual(session.bufferedByteCount, 9)
        XCTAssertEqual(
            try session.receive(Data(encoded.dropFirst(9))),
            [.peerHelloAnswer(hello)]
        )
        XCTAssertEqual(session.bufferedByteCount, 0)
    }

    func testReceiveMapsPartRequestAndSendingPartPackets() throws {
        var session = ED2KPeerSession(configuration: makeConfiguration())
        let fileHash = Data(0..<16)
        let requestPacket = try ED2KPartRequest(
            fileHash: fileHash,
            ranges: [
                ED2KPartRange(startOffset: 0, endOffset: 1024),
                ED2KPartRange(startOffset: 4096, endOffset: 6144)
            ]
        ).packet()

        var sendingPayload = Data(fileHash)
        sendingPayload.append(contentsOf: [0x00, 0x10, 0x00, 0x00])
        sendingPayload.append(contentsOf: [0x04, 0x10, 0x00, 0x00])
        sendingPayload.append(Data(repeating: 0xAB, count: 4))
        let sendingPacket = ED2KPacket(
            opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
            payload: sendingPayload
        )

        var bytes = Data()
        bytes.append(requestPacket.encoded())
        bytes.append(sendingPacket.encoded())

        XCTAssertEqual(
            try session.receive(bytes),
            [
                .partRequest(
                    try ED2KPartRequest(
                        fileHash: fileHash,
                        ranges: [
                            ED2KPartRange(startOffset: 0, endOffset: 1024),
                            ED2KPartRange(startOffset: 4096, endOffset: 6144)
                        ]
                    )
                ),
                .sendingPart(
                    ED2KSendingPart(
                        fileHash: fileHash,
                        startOffset: 4096,
                        endOffset: 4100,
                        block: Data(repeating: 0xAB, count: 4)
                    )
                )
            ]
        )
    }

    func testReceiveMapsPartHashSetReply() throws {
        var session = ED2KPeerSession(configuration: makeConfiguration())
        var payload = Data(0..<16)
        payload.append(contentsOf: [0x02, 0x00])
        payload.append(Data(repeating: 0x11, count: 16))
        payload.append(Data(repeating: 0x22, count: 16))
        let packet = ED2KPacket(
            opcode: ED2KPeerPacketOpcode.hashSetAnswer.rawValue,
            payload: payload
        )

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [
                .partHashSet(
                    ED2KPartHashSet(
                        fileHash: Data(0..<16),
                        partHashes: [
                            Data(repeating: 0x11, count: 16),
                            Data(repeating: 0x22, count: 16)
                        ]
                    )
                )
            ]
        )
    }

    func testReceiveMapsSourceExchangeAnswer() throws {
        var session = ED2KPeerSession(configuration: makeConfiguration())
        var payload = Data([0x04])
        payload.append(Data(0..<16))
        payload.append(contentsOf: [0x01, 0x00])
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(Data(repeating: 0xAB, count: 16))
        payload.append(0)
        let packet = ED2KPacket(
            protocolByte: .emule,
            opcode: ED2KPeerPacketOpcode.answerSources2.rawValue,
            payload: payload
        )

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [
                .sourceExchangeAnswer(
                    ED2KPeerSourceExchangeAnswer(
                        version: 4,
                        fileHash: Data(0..<16),
                        sources: [
                            ED2KPeerSourceExchangeSource(
                                clientID: 0x01020304,
                                clientPort: 4662,
                                serverEndpoint: nil,
                                userHash: Data(repeating: 0xAB, count: 16),
                                cryptOptions: 0
                            )
                        ]
                    )
                )
            ]
        )
    }

    func testReceiveMapsUploadSlotAndQueuePackets() throws {
        var session = ED2KPeerSession(configuration: makeConfiguration())
        var bytes = Data()
        bytes.append(
            ED2KPacket(opcode: ED2KPeerPacketOpcode.acceptUploadRequest.rawValue).encoded()
        )
        bytes.append(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.queueRank.rawValue,
                payload: Data([0x39, 0x30, 0x00, 0x00])
            ).encoded()
        )

        XCTAssertEqual(
            try session.receive(bytes),
            [
                .acceptUploadRequest,
                .queueRank(12_345)
            ]
        )
    }

    func testFileCommandPacketsUseFileHashPayloads() throws {
        let session = ED2KPeerSession(configuration: makeConfiguration())
        let fileHash = Data(0..<16)

        XCTAssertEqual(
            try session.fileRequestPacket(fileHash: fileHash),
            ED2KPacket(opcode: ED2KPeerPacketOpcode.requestFileName.rawValue, payload: fileHash)
        )
        XCTAssertEqual(
            try session.setRequestFileIDPacket(fileHash: fileHash),
            ED2KPacket(opcode: ED2KPeerPacketOpcode.setRequestFileID.rawValue, payload: fileHash)
        )
        XCTAssertEqual(
            try session.startUploadRequestPacket(fileHash: fileHash),
            ED2KPacket(opcode: ED2KPeerPacketOpcode.startUploadRequest.rawValue, payload: fileHash)
        )
    }

    func testReceiveKeepsUnknownPeerPacketsAsUnhandled() throws {
        var session = ED2KPeerSession(configuration: makeConfiguration())
        let packet = ED2KPacket(opcode: 0x99, payload: Data([0x01, 0x02]))

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [.unhandledPacket(packet)]
        )
    }

    private func makeConfiguration() -> ED2KPeerSessionConfiguration {
        ED2KPeerSessionConfiguration(
            userHash: Data(0..<16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "MacMule Test",
            version: "MacMule/0.1",
            serverEndpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        )
    }
}
