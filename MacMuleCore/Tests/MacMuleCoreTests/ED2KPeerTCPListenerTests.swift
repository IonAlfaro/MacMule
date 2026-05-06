import XCTest
@testable import MacMuleCore

final class ED2KPeerTCPListenerTests: XCTestCase {
    func testListenerAcceptsIncomingPeerHelloAndRepliesWithHelloAnswer() throws {
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let acceptedTransport = FakeED2KPeerTCPTransport()
        let endpoint = ED2KPeerEndpoint(host: "203.0.113.40", port: 4662)
        let configuration = ED2KPeerSessionConfiguration(
            userHash: Data(0..<16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "MacMule Test",
            version: "MacMule/0.1",
            serverEndpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        )
        var events: [ED2KPeerTCPListenerEvent] = []
        let listener = ED2KPeerTCPListener(
            configuration: configuration,
            transport: listenerTransport
        ) { event in
            events.append(event)
        }

        listener.start()
        listenerTransport.simulateState(.ready(4662))
        listenerTransport.simulateAcceptedConnection(
            ED2KAcceptedPeerConnection(endpoint: endpoint, transport: acceptedTransport)
        )
        acceptedTransport.simulateState(.ready)

        let peerHello = try ED2KPeerHello(
            userHash: Data(16..<32),
            clientID: 0x05060708,
            tcpPort: 4662,
            nickname: "Peer Mule",
            version: "PeerMule/1.0",
            serverEndpoint: ED2KServerEndpoint(host: "198.51.100.50", port: 4661)
        )
        acceptedTransport.simulateReceive(try peerHello.packet(opcode: .hello).encoded())

        XCTAssertTrue(listenerTransport.startCalled)
        XCTAssertTrue(events.contains(.stateChanged(.starting(4662))))
        XCTAssertTrue(events.contains(.stateChanged(.listening(4662))))
        XCTAssertTrue(events.contains(.accepted(endpoint)))
        XCTAssertTrue(events.contains(.sessionEvent(endpoint, .peerHello(peerHello))))
        XCTAssertTrue(events.contains(.helloAnswerSent(endpoint)))
        XCTAssertEqual(
            acceptedTransport.sentData,
            [try configuration.hello().packet(opcode: .helloAnswer).encoded()]
        )
    }
}

private final class FakeED2KPeerTCPListenerTransport: ED2KPeerTCPListenerTransport {
    var stateUpdateHandler: ((ED2KPeerTCPListenerTransportState) -> Void)?
    var connectionHandler: ((ED2KAcceptedPeerConnection) -> Void)?

    private(set) var startCalled = false
    private(set) var cancelCalled = false

    func start(queue: DispatchQueue) {
        startCalled = true
    }

    func cancel() {
        cancelCalled = true
    }

    func simulateState(_ state: ED2KPeerTCPListenerTransportState) {
        stateUpdateHandler?(state)
    }

    func simulateAcceptedConnection(_ connection: ED2KAcceptedPeerConnection) {
        connectionHandler?(connection)
    }
}

private final class FakeED2KPeerTCPTransport: ED2KPeerTCPTransport {
    var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)?
    var receiveHandler: ((Data) -> Void)?

    private(set) var sentData: [Data] = []
    private(set) var receiveNextCallCount = 0
    private(set) var cancelCalled = false

    func start(queue: DispatchQueue) {}

    func send(_ data: Data, completion: @escaping @Sendable (ED2KPeerTCPTransportSendResult) -> Void) {
        sentData.append(data)
        completion(.sent)
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
