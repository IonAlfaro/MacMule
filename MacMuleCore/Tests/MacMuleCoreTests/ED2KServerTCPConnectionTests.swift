import XCTest
@testable import MacMuleCore

final class ED2KServerTCPConnectionTests: XCTestCase {
    func testStartSendsLoginWhenTransportBecomesReady() throws {
        let configuration = makeConfiguration()
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        let loginPacket = try configuration.loginRequest().packet()
        XCTAssertTrue(transport.startCalled)
        XCTAssertEqual(transport.sentData, [loginPacket.encoded()])
        XCTAssertEqual(transport.receiveNextCallCount, 1)
        XCTAssertEqual(
            events,
            [
                .stateChanged(.connecting),
                .stateChanged(.connected),
                .sessionEvent(.outgoingLogin(loginPacket)),
                .loginSent
            ]
        )
    }

    func testIncomingBytesBecomeSessionEvents() throws {
        let configuration = makeConfiguration()
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }
        let message = ED2KServerMessage(rawText: "server version 17.15")
        let packet = ED2KPacket(
            opcode: .serverMessage,
            payload: serverMessagePayload(message.rawText)
        )

        connection.start()
        transport.simulateState(.ready)
        transport.simulateReceive(packet.encoded())

        XCTAssertTrue(events.contains(.sessionEvent(.serverMessage(message))))
        XCTAssertEqual(transport.receiveNextCallCount, 2)
    }

    func testLoginSendFailureEmitsLoginFailed() throws {
        let configuration = makeConfiguration()
        let transport = FakeED2KServerTCPTransport(sendResult: .failed("no route"))
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        XCTAssertTrue(events.contains(.loginFailed("no route")))
        XCTAssertFalse(events.contains(.loginSent))
    }

    func testSendSearchAfterReadyWritesSearchPacket() throws {
        let configuration = makeConfiguration()
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        XCTAssertTrue(connection.sendSearch(query: "ubuntu iso"))
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KSearchRequest(query: "ubuntu iso").packet().encoded())
        XCTAssertTrue(events.contains(.searchSent("ubuntu iso")))
    }

    func testSendEmptyOfferFilesAfterReadyWritesZeroCountOfferPacket() throws {
        let configuration = makeConfiguration()
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        XCTAssertTrue(connection.sendEmptyOfferFiles())
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(
            Array(transport.sentData[1]),
            [0xE3, 0x05, 0x00, 0x00, 0x00, 0x15, 0x00, 0x00, 0x00, 0x00]
        )
        XCTAssertTrue(events.contains(.emptyOfferFilesSent))
    }

    func testSendSourceLookupAfterReadyWritesSourcePacket() throws {
        let configuration = makeConfiguration()
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.ready)

        let fileHash = Data((0..<16).map(UInt8.init))
        XCTAssertTrue(connection.sendSourceLookup(fileHash: fileHash, fileSizeInBytes: 1024))
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(
            transport.sentData[1],
            try ED2KSourceRequest(fileHash: fileHash, fileSizeInBytes: 1024).packet().encoded()
        )
        XCTAssertTrue(events.contains(.sourceLookupSent("000102030405060708090A0B0C0D0E0F")))
    }

    func testTransportFailureEmitsFailedState() {
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
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

    func testTransportWaitingEmitsWaitingState() {
        let transport = FakeED2KServerTCPTransport()
        var events: [ED2KServerTCPConnectionEvent] = []
        let connection = ED2KServerTCPConnection(
            configuration: makeConfiguration(),
            transport: transport
        ) { event in
            events.append(event)
        }

        connection.start()
        transport.simulateState(.waiting("dns lookup"))

        XCTAssertEqual(
            events,
            [
                .stateChanged(.connecting),
                .stateChanged(.waiting("dns lookup"))
            ]
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
}

private final class FakeED2KServerTCPTransport: ED2KServerTCPTransport {
    var stateUpdateHandler: ((ED2KServerTCPTransportState) -> Void)?
    var receiveHandler: ((Data) -> Void)?
    var logHandler: (@Sendable (String) -> Void)?

    private let sendResult: ED2KServerTCPTransportSendResult
    private(set) var startCalled = false
    private(set) var sentData: [Data] = []
    private(set) var receiveNextCallCount = 0
    private(set) var cancelCalled = false

    init(sendResult: ED2KServerTCPTransportSendResult = .sent) {
        self.sendResult = sendResult
    }

    func start(queue: DispatchQueue) {
        startCalled = true
    }

    func send(_ data: Data, completion: @escaping @Sendable (ED2KServerTCPTransportSendResult) -> Void) {
        sentData.append(data)
        completion(sendResult)
    }

    func receiveNext() {
        receiveNextCallCount += 1
    }

    func cancel() {
        cancelCalled = true
    }

    func simulateState(_ state: ED2KServerTCPTransportState) {
        stateUpdateHandler?(state)
    }

    func simulateReceive(_ data: Data) {
        receiveHandler?(data)
    }
}
