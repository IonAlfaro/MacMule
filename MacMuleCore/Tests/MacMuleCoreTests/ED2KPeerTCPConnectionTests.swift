import XCTest
@testable import MacMuleCore

final class ED2KPeerTCPConnectionTests: XCTestCase {
    func testStartSendsHelloWhenTransportBecomesReady() throws {
        let configuration = makeConfiguration()
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.10", port: 4662)
        let transport = FakeED2KPeerTCPTransport()
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: endpoint,
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        let helloPacket = try configuration.hello().packet(opcode: .hello)
        XCTAssertTrue(transport.startCalled)
        XCTAssertEqual(transport.sentData, [helloPacket.encoded()])
        XCTAssertEqual(transport.receiveNextCallCount, 1)
        XCTAssertEqual(
            events,
            [
                .stateChanged(.connecting),
                .stateChanged(.connected),
                .sessionEvent(.outgoingHello(helloPacket)),
                .helloSent
            ]
        )
    }

    func testIncomingBytesBecomePeerSessionEvents() throws {
        let configuration = makeConfiguration()
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.10", port: 4662)
        let transport = FakeED2KPeerTCPTransport()
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: endpoint,
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }
        let helloAnswer = try ED2KPeerHello(
            userHash: Data(0..<16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "Peer Mule",
            version: "PeerMule/1.0",
            serverEndpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        )
        let packet = try helloAnswer.packet(opcode: .helloAnswer)

        connection.start()
        transport.simulateState(.ready)
        transport.simulateReceive(packet.encoded())

        XCTAssertTrue(events.contains(.sessionEvent(.peerHelloAnswer(helloAnswer))))
        XCTAssertEqual(transport.receiveNextCallCount, 2)
    }

    func testHelloSendFailureEmitsHelloFailed() {
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.10", port: 4662)
        let transport = FakeED2KPeerTCPTransport(sendResult: .failed("no route"))
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: endpoint,
            configuration: makeConfiguration(),
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        XCTAssertTrue(events.contains(.helloFailed("no route")))
        XCTAssertFalse(events.contains(.helloSent))
    }

    func testSendPartRequestAfterReadyWritesRequestPacket() throws {
        let configuration = makeConfiguration()
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.10", port: 4662)
        let transport = FakeED2KPeerTCPTransport()
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: endpoint,
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        let fileHash = Data((0..<16).map(UInt8.init))
        let ranges = [ED2KPartRange(startOffset: 0, endOffset: 1024)]
        XCTAssertTrue(connection.sendPartRequest(fileHash: fileHash, ranges: ranges))
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KPartRequest(fileHash: fileHash, ranges: ranges).packet().encoded())
        XCTAssertTrue(events.contains(.partRequestSent("000102030405060708090A0B0C0D0E0F")))
    }

    func testSendPartHashSetRequestAfterReadyWritesRequestPacket() throws {
        let configuration = makeConfiguration()
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.10", port: 4662)
        let transport = FakeED2KPeerTCPTransport()
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: endpoint,
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        let fileHash = Data((0..<16).map(UInt8.init))
        XCTAssertTrue(connection.sendPartHashSetRequest(fileHash: fileHash))
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KPartHashSetRequest(fileHash: fileHash).packet().encoded())
        XCTAssertTrue(events.contains(.partHashSetRequestSent("000102030405060708090A0B0C0D0E0F")))
    }

    func testSendSourceExchangeRequestAfterReadyWritesSX2Packet() throws {
        let configuration = makeConfiguration()
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.10", port: 4662)
        let transport = FakeED2KPeerTCPTransport()
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: endpoint,
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        let fileHash = Data((0..<16).map(UInt8.init))
        XCTAssertTrue(connection.sendSourceExchangeRequest(fileHash: fileHash))
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KPeerSourceExchangeRequest(fileHash: fileHash).packet().encoded())
        XCTAssertTrue(events.contains(.sourceExchangeRequestSent("000102030405060708090A0B0C0D0E0F")))
    }

    func testTransportFailureEmitsFailedState() {
        let transport = FakeED2KPeerTCPTransport()
        var events: [ED2KPeerTCPConnectionEvent] = []
        let connection = ED2KPeerTCPConnection(
            endpoint: ED2KPeerEndpoint(host: "203.0.113.10", port: 4662),
            configuration: makeConfiguration(),
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.failed("connection refused"))

        XCTAssertEqual(
            events,
            [
                .stateChanged(.connecting),
                .stateChanged(.failed("connection refused"))
            ]
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

private final class FakeED2KPeerTCPTransport: ED2KPeerTCPTransport {
    var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)?
    var receiveHandler: ((Data) -> Void)?

    private let sendResult: ED2KPeerTCPTransportSendResult
    private(set) var startCalled = false
    private(set) var sentData: [Data] = []
    private(set) var receiveNextCallCount = 0
    private(set) var cancelCalled = false

    init(sendResult: ED2KPeerTCPTransportSendResult = .sent) {
        self.sendResult = sendResult
    }

    func start(queue: DispatchQueue) {
        startCalled = true
    }

    func send(_ data: Data, completion: @escaping @Sendable (ED2KPeerTCPTransportSendResult) -> Void) {
        sentData.append(data)
        completion(sendResult)
    }

    func receiveNext() {
        receiveNextCallCount += 1
    }

    func cancel() {
        cancelCalled = true
    }

    func simulateState(_ state: ED2KPeerTCPTransportState) {
        stateUpdateHandler?(state)
    }

    func simulateReceive(_ data: Data) {
        receiveHandler?(data)
    }
}
