import Foundation
import Network

public enum ED2KPeerTCPListenerState: Equatable, Sendable {
    case starting(UInt16)
    case listening(UInt16)
    case failed(String)
    case cancelled
}

public enum ED2KPeerTCPListenerEvent: Equatable, Sendable {
    case stateChanged(ED2KPeerTCPListenerState)
    case accepted(ED2KPeerEndpoint)
    case sessionEvent(ED2KPeerEndpoint, ED2KPeerSessionEvent)
    case helloAnswerSent(ED2KPeerEndpoint)
    case helloAnswerFailed(endpoint: ED2KPeerEndpoint, message: String)
    case receiveFailed(endpoint: ED2KPeerEndpoint, message: String)
}

public enum ED2KPeerTCPListenerTransportState: Equatable, Sendable {
    case ready(UInt16)
    case failed(String)
    case cancelled
}

public struct ED2KAcceptedPeerConnection {
    public let endpoint: ED2KPeerEndpoint
    public let transport: ED2KPeerTCPTransport

    public init(endpoint: ED2KPeerEndpoint, transport: ED2KPeerTCPTransport) {
        self.endpoint = endpoint
        self.transport = transport
    }
}

public protocol ED2KPeerTCPListenerTransport: AnyObject {
    var stateUpdateHandler: ((ED2KPeerTCPListenerTransportState) -> Void)? { get set }
    var connectionHandler: ((ED2KAcceptedPeerConnection) -> Void)? { get set }

    func start(queue: DispatchQueue)
    func cancel()
}

public final class NoopED2KPeerTCPListenerTransport: ED2KPeerTCPListenerTransport {
    public var stateUpdateHandler: ((ED2KPeerTCPListenerTransportState) -> Void)?
    public var connectionHandler: ((ED2KAcceptedPeerConnection) -> Void)?

    public init() {}

    public func start(queue: DispatchQueue) {}

    public func cancel() {
        stateUpdateHandler?(.cancelled)
    }
}

public final class ED2KPeerTCPListener: @unchecked Sendable {
    public let configuration: ED2KPeerSessionConfiguration

    private let transport: ED2KPeerTCPListenerTransport
    private let queue: DispatchQueue
    private let eventHandler: (ED2KPeerTCPListenerEvent) -> Void
    private let stateLock = NSLock()
    private var incomingConnections: [UUID: IncomingPeerConnection] = [:]

    public convenience init(
        configuration: ED2KPeerSessionConfiguration,
        queue: DispatchQueue = DispatchQueue(label: "MacMule.ED2KPeerTCPListener"),
        eventHandler: @escaping (ED2KPeerTCPListenerEvent) -> Void
    ) {
        self.init(
            configuration: configuration,
            transport: NetworkED2KPeerTCPListenerTransport(port: configuration.tcpPort),
            queue: queue,
            eventHandler: eventHandler
        )
    }

    public init(
        configuration: ED2KPeerSessionConfiguration,
        transport: ED2KPeerTCPListenerTransport,
        queue: DispatchQueue = DispatchQueue(label: "MacMule.ED2KPeerTCPListener"),
        eventHandler: @escaping (ED2KPeerTCPListenerEvent) -> Void
    ) {
        self.configuration = configuration
        self.transport = transport
        self.queue = queue
        self.eventHandler = eventHandler
    }

    public func start() {
        emit(.stateChanged(.starting(configuration.tcpPort)))
        transport.stateUpdateHandler = { [weak self] state in
            self?.handleTransportState(state)
        }
        transport.connectionHandler = { [weak self] acceptedConnection in
            self?.handleAcceptedConnection(acceptedConnection)
        }
        transport.start(queue: queue)
    }

    public func cancel() {
        let connections = withStateLock {
            let values = Array(incomingConnections.values)
            incomingConnections.removeAll()
            return values
        }
        connections.forEach { $0.cancel() }
        transport.cancel()
    }

    private func handleTransportState(_ state: ED2KPeerTCPListenerTransportState) {
        switch state {
        case .ready(let port):
            emit(.stateChanged(.listening(port)))
        case .failed(let message):
            emit(.stateChanged(.failed(message)))
        case .cancelled:
            emit(.stateChanged(.cancelled))
        }
    }

    private func handleAcceptedConnection(_ acceptedConnection: ED2KAcceptedPeerConnection) {
        let identifier = UUID()
        let connection = IncomingPeerConnection(
            endpoint: acceptedConnection.endpoint,
            configuration: configuration,
            transport: acceptedConnection.transport
        ) { [weak self] event in
            self?.emit(event)
        } onFinished: { [weak self] in
            self?.removeIncomingConnection(identifier)
        }

        withStateLock {
            incomingConnections[identifier] = connection
        }

        emit(.accepted(acceptedConnection.endpoint))
        connection.start(queue: queue)
    }

    private func removeIncomingConnection(_ identifier: UUID) {
        _ = withStateLock {
            incomingConnections.removeValue(forKey: identifier)
        }
    }

    private func emit(_ event: ED2KPeerTCPListenerEvent) {
        eventHandler(event)
    }

    private func withStateLock<T>(_ work: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return work()
    }
}

private final class IncomingPeerConnection: @unchecked Sendable {
    private let endpoint: ED2KPeerEndpoint
    private var session: ED2KPeerSession
    private let transport: ED2KPeerTCPTransport
    private let eventHandler: (ED2KPeerTCPListenerEvent) -> Void
    private let onFinished: () -> Void

    init(
        endpoint: ED2KPeerEndpoint,
        configuration: ED2KPeerSessionConfiguration,
        transport: ED2KPeerTCPTransport,
        eventHandler: @escaping (ED2KPeerTCPListenerEvent) -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.endpoint = endpoint
        session = ED2KPeerSession(configuration: configuration)
        self.transport = transport
        self.eventHandler = eventHandler
        self.onFinished = onFinished
    }

    func start(queue: DispatchQueue) {
        transport.stateUpdateHandler = { [weak self] state in
            self?.handleTransportState(state)
        }
        transport.receiveHandler = { [weak self] data in
            self?.handleReceivedData(data)
        }
        transport.start(queue: queue)
    }

    func cancel() {
        transport.cancel()
    }

    private func handleTransportState(_ state: ED2KPeerTCPTransportState) {
        switch state {
        case .ready:
            transport.receiveNext()
        case .waiting:
            break
        case .failed(let message):
            eventHandler(.receiveFailed(endpoint: endpoint, message: message))
            onFinished()
        case .cancelled:
            onFinished()
        }
    }

    private func handleReceivedData(_ data: Data) {
        do {
            let events = try session.receive(data)
            for event in events {
                eventHandler(.sessionEvent(endpoint, event))
                if case .peerHello = event {
                    try sendHelloAnswer()
                }
            }
            transport.receiveNext()
        } catch {
            eventHandler(.receiveFailed(endpoint: endpoint, message: error.localizedDescription))
            transport.cancel()
        }
    }

    private func sendHelloAnswer() throws {
        let packet = try session.helloAnswerPacket()
        eventHandler(.sessionEvent(endpoint, .outgoingHelloAnswer(packet)))
        transport.send(packet.encoded()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .sent:
                self.eventHandler(.helloAnswerSent(self.endpoint))
            case .failed(let message):
                self.eventHandler(.helloAnswerFailed(endpoint: self.endpoint, message: message))
                self.transport.cancel()
            }
        }
    }
}

public final class NetworkED2KPeerTCPListenerTransport: ED2KPeerTCPListenerTransport, @unchecked Sendable {
    public var stateUpdateHandler: ((ED2KPeerTCPListenerTransportState) -> Void)?
    public var connectionHandler: ((ED2KAcceptedPeerConnection) -> Void)?

    private let listener: NWListener?
    private let initializationError: String?

    public init(port: UInt16, parameters: NWParameters = .tcp) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            listener = nil
            initializationError = "Invalid eD2k peer listener port: \(port)"
            return
        }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
            initializationError = nil
        } catch {
            listener = nil
            initializationError = String(describing: error)
        }
    }

    public func start(queue: DispatchQueue) {
        guard let listener else {
            stateUpdateHandler?(.failed(initializationError ?? "Unknown listener initialization error"))
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleState(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener?.cancel()
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            let port = listener?.port?.rawValue ?? 0
            stateUpdateHandler?(.ready(port))
        case .failed(let error):
            stateUpdateHandler?(.failed(String(describing: error)))
        case .cancelled:
            stateUpdateHandler?(.cancelled)
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let endpoint = Self.endpoint(for: connection.endpoint)
        connectionHandler?(
            ED2KAcceptedPeerConnection(
                endpoint: endpoint,
                transport: AcceptedNetworkED2KPeerTCPTransport(connection: connection)
            )
        )
    }

    private static func endpoint(for endpoint: NWEndpoint) -> ED2KPeerEndpoint {
        switch endpoint {
        case .hostPort(let host, let port):
            return ED2KPeerEndpoint(host: host.debugDescription, port: port.rawValue)
        default:
            return ED2KPeerEndpoint(host: "unknown", port: 0)
        }
    }
}

private final class AcceptedNetworkED2KPeerTCPTransport: ED2KPeerTCPTransport, @unchecked Sendable {
    var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)?
    var receiveHandler: ((Data) -> Void)?

    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleState(state)
        }
        connection.start(queue: queue)
    }

    func send(_ data: Data, completion: @escaping @Sendable (ED2KPeerTCPTransportSendResult) -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                completion(.failed(String(describing: error)))
            } else {
                completion(.sent)
            }
        })
    }

    func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if let data, data.isEmpty == false {
                self?.receiveHandler?(data)
                return
            }

            if let error {
                self?.stateUpdateHandler?(.failed(String(describing: error)))
                return
            }

            if isComplete {
                self?.stateUpdateHandler?(.cancelled)
            }
        }
    }

    func cancel() {
        connection.cancel()
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            stateUpdateHandler?(.ready)
        case .waiting(let error):
            stateUpdateHandler?(.waiting(String(describing: error)))
        case .failed(let error):
            stateUpdateHandler?(.failed(String(describing: error)))
        case .cancelled:
            stateUpdateHandler?(.cancelled)
        default:
            break
        }
    }
}
