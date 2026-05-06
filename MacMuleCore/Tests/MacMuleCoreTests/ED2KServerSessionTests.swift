import XCTest
@testable import MacMuleCore

final class ED2KServerSessionTests: XCTestCase {
    func testLoginEventUsesConfiguration() throws {
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16),
            tcpPort: 4670,
            nickname: "MacMule Test",
            protocolVersion: 61,
            flags: 3
        )
        let session = ED2KServerSession(configuration: configuration)
        let expectedPacket = try configuration.loginRequest().packet()

        XCTAssertEqual(try session.loginEvent(), .outgoingLogin(expectedPacket))
        XCTAssertEqual(try session.loginBytes(), expectedPacket.encoded())
    }

    func testReceiveBuffersPartialServerMessage() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        let packet = ED2KPacket(
            opcode: .serverMessage,
            payload: serverMessagePayload("server version 17.15\r\nwelcome")
        )
        let encoded = packet.encoded()

        XCTAssertEqual(try session.receive(Data(encoded.prefix(7))), [])
        XCTAssertEqual(session.bufferedByteCount, 7)
        XCTAssertEqual(
            try session.receive(Data(encoded.dropFirst(7))),
            [.serverMessage(ED2KServerMessage(rawText: "server version 17.15\r\nwelcome"))]
        )
        XCTAssertEqual(session.bufferedByteCount, 0)
    }

    func testReceiveMapsServerIdentityAndServerListPackets() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        let identityHash = Data(0..<16)
        let identityPacket = ED2KPacket(
            opcode: .serverIdent,
            payload: serverIdentityPayload(hash: identityHash, hostOctets: [127, 0, 0, 1], port: 4661)
        )
        let listPacket = ED2KPacket(
            opcode: .serverList,
            payload: Data([0x01, 0x5B, 0x79, 0x4F, 0x23, 0x36, 0x12])
        )
        var bytes = Data()
        bytes.append(identityPacket.encoded())
        bytes.append(listPacket.encoded())

        XCTAssertEqual(
            try session.receive(bytes),
            [
                .serverIdentity(
                    ED2KServerIdentity(
                        hash: identityHash,
                        endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
                    )
                ),
                .serverList([ED2KServerEndpoint(host: "91.121.79.35", port: 4662)])
            ]
        )
    }

    func testReceiveMapsIDChangePacket() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        var payload = Data()
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x1D, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [0x7F, 0x00, 0x00, 0x01])
        payload.append(contentsOf: [0xB8, 0x1A, 0x00, 0x00])
        let packet = ED2KPacket(opcode: .idChange, payload: payload)

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [
                .idChange(
                    ED2KIDChange(
                        clientID: 0x01020304,
                        tcpFlags: 0x1D,
                        auxiliaryTCPPort: 0,
                        serverReportedIP: 0x0100007F,
                        obfuscationTCPPort: 6840
                    )
                )
            ]
        )
    }

    func testReceiveMapsSearchResultPackets() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        let packet = ED2KPacket(
            opcode: .searchResults,
            payload: searchResultPayload()
        )

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [
                .searchResults([
                    ED2KSearchResult(
                        fileHash: Data(0..<16),
                        clientID: 0x01020304,
                        clientPort: 4662,
                        tags: [
                            ED2KTag(name: ED2KSearchTagName.fileName, value: .string("Ubuntu.iso")),
                            ED2KTag(name: ED2KSearchTagName.fileSize, value: .uint32(1024))
                        ]
                    )
                ])
            ]
        )
    }

    func testReceiveMapsLegacySearchOpcodeAsSearchResults() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        let packet = ED2KPacket(
            opcode: .search,
            payload: searchResultPayload()
        )

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [
                .searchResults([
                    ED2KSearchResult(
                        fileHash: Data(0..<16),
                        clientID: 0x01020304,
                        clientPort: 4662,
                        tags: [
                            ED2KTag(name: ED2KSearchTagName.fileName, value: .string("Ubuntu.iso")),
                            ED2KTag(name: ED2KSearchTagName.fileSize, value: .uint32(1024))
                        ]
                    )
                ])
            ]
        )
    }

    func testReceiveMapsFoundSourcesPackets() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        let packet = ED2KPacket(
            opcode: .foundSources,
            payload: foundSourcesPayload()
        )

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [
                .foundSources(
                    ED2KFoundSources(
                        fileHash: Data(0..<16),
                        sources: [
                            ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
                            ED2KFoundSource(clientID: 0x05060708, clientPort: 4672)
                        ]
                    )
                )
            ]
        )
    }

    func testReceiveKeepsUnknownPacketsAsUnhandled() throws {
        var session = ED2KServerSession(configuration: makeConfiguration())
        let packet = ED2KPacket(opcode: 0x99, payload: Data([1, 2, 3]))

        XCTAssertEqual(
            try session.receive(packet.encoded()),
            [.unhandledPacket(packet)]
        )
    }

    private func makeConfiguration() -> ED2KServerSessionConfiguration {
        ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
    }

    private func serverMessagePayload(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        var payload = Data()
        payload.append(UInt8(bytes.count & 0x00FF))
        payload.append(UInt8((bytes.count >> 8) & 0x00FF))
        payload.append(bytes)
        return payload
    }

    private func serverIdentityPayload(hash: Data, hostOctets: [UInt8], port: UInt16) -> Data {
        var payload = Data()
        payload.append(hash)
        payload.append(contentsOf: hostOctets)
        payload.append(UInt8(port & 0x00FF))
        payload.append(UInt8((port >> 8) & 0x00FF))
        return payload
    }

    private func searchResultPayload() -> Data {
        var payload = Data()
        payload.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        payload.append(Data(0..<16))
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
        payload.append(ED2KTag(name: ED2KSearchTagName.fileName, value: .string("Ubuntu.iso")).encoded())
        payload.append(ED2KTag(name: ED2KSearchTagName.fileSize, value: .uint32(1024)).encoded())
        return payload
    }

    private func foundSourcesPayload() -> Data {
        var payload = Data(0..<16)
        payload.append(0x02)
        payload.append(contentsOf: [0x04, 0x03, 0x02, 0x01])
        payload.append(contentsOf: [0x36, 0x12])
        payload.append(contentsOf: [0x08, 0x07, 0x06, 0x05])
        payload.append(contentsOf: [0x40, 0x12])
        return payload
    }
}
