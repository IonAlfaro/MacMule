import Foundation
import Network

public enum ED2KPeerTCPConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case disconnected
    case failed(String)
}

public enum ED2KPeerTCPConnectionEvent: Equatable, Sendable {
    case stateChanged(ED2KPeerTCPConnectionState)
    case sessionEvent(ED2KPeerSessionEvent)
    case helloSent
    case helloFailed(String)
    case fileRequestSent(String)
    case fileRequestFailed(hash: String, message: String)
    case setRequestFileIDSent(String)
    case setRequestFileIDFailed(hash: String, message: String)
    case startUploadRequestSent(String)
    case startUploadRequestFailed(hash: String, message: String)
    case sourceExchangeRequestSent(String)
    case sourceExchangeRequestFailed(hash: String, message: String)
    case partHashSetRequestSent(String)
    case partHashSetRequestFailed(hash: String, message: String)
    case partRequestSent(String)
    case partRequestFailed(hash: String, message: String)
    case receiveFailed(String)
}

public enum ED2KPeerTCPTransportState: Equatable, Sendable {
    case ready
    case waiting(String)
    case failed(String)
    case cancelled
}

public enum ED2KPeerTCPTransportSendResult: Equatable, Sendable {
    case sent
    case failed(String)
}

public protocol ED2KPeerTCPTransport: AnyObject {
    var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)? { get set }
    var receiveHandler: ((Data) -> Void)? { get set }

    func start(queue: DispatchQueue)
    func send(_ data: Data, completion: @escaping @Sendable (ED2KPeerTCPTransportSendResult) -> Void)
    func receiveNext()
    func cancel()
}

public final class ED2KPeerTCPConnection: @unchecked Sendable {
    public let endpoint: ED2KPeerEndpoint
    public let configuration: ED2KPeerSessionConfiguration

    private var session: ED2KPeerSession
    private let transport: ED2KPeerTCPTransport
    private let queue: DispatchQueue
    private let eventHandler: (ED2KPeerTCPConnectionEvent) -> Void
    private let stateLock = NSLock()
    private var isReady = false

    public convenience init(
        endpoint: ED2KPeerEndpoint,
        configuration: ED2KPeerSessionConfiguration,
        queue: DispatchQueue = DispatchQueue(label: "MacMule.ED2KPeerTCPConnection"),
        eventHandler: @escaping (ED2KPeerTCPConnectionEvent) -> Void
    ) {
        self.init(
            endpoint: endpoint,
            configuration: configuration,
            transport: NetworkED2KPeerTCPTransport(endpoint: endpoint),
            queue: queue,
            eventHandler: eventHandler
        )
    }

    public init(
        endpoint: ED2KPeerEndpoint,
        configuration: ED2KPeerSessionConfiguration,
        transport: ED2KPeerTCPTransport,
        queue: DispatchQueue = DispatchQueue(label: "MacMule.ED2KPeerTCPConnection"),
        eventHandler: @escaping (ED2KPeerTCPConnectionEvent) -> Void
    ) {
        self.endpoint = endpoint
        self.configuration = configuration
        session = ED2KPeerSession(configuration: configuration)
        self.transport = transport
        self.queue = queue
        self.eventHandler = eventHandler
    }

    public func start() {
        emit(.stateChanged(.connecting))

        transport.stateUpdateHandler = { [weak self] state in
            self?.handleTransportState(state)
        }
        transport.receiveHandler = { [weak self] data in
            self?.handleReceivedData(data)
        }
        transport.start(queue: queue)
    }

    public func cancel() {
        withStateLock {
            isReady = false
        }
        transport.cancel()
    }

    @discardableResult
    public func sendPartRequest(fileHash: Data, ranges: [ED2KPartRange]) -> Bool {
        let hashText = fileHash.hexadecimalString

        guard withStateLock({ isReady }) else {
            emit(.partRequestFailed(hash: hashText, message: "Part request requested before the peer connection became ready."))
            return false
        }

        do {
            let packet = try session.partRequestPacket(fileHash: fileHash, ranges: ranges)
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(.partRequestSent(hashText))
                case .failed(let message):
                    self?.emit(.partRequestFailed(hash: hashText, message: message))
                }
            }
            return true
        } catch {
            emit(.partRequestFailed(hash: hashText, message: error.localizedDescription))
            return false
        }
    }

    @discardableResult
    public func sendPartHashSetRequest(fileHash: Data) -> Bool {
        let hashText = fileHash.hexadecimalString

        guard withStateLock({ isReady }) else {
            emit(.partHashSetRequestFailed(hash: hashText, message: "Hashset request requested before the peer connection became ready."))
            return false
        }

        do {
            let packet = try session.partHashSetRequestPacket(fileHash: fileHash)
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(.partHashSetRequestSent(hashText))
                case .failed(let message):
                    self?.emit(.partHashSetRequestFailed(hash: hashText, message: message))
                }
            }
            return true
        } catch {
            emit(.partHashSetRequestFailed(hash: hashText, message: error.localizedDescription))
            return false
        }
    }

    @discardableResult
    public func sendFileRequest(fileHash: Data) -> Bool {
        sendPeerFileCommand(
            fileHash: fileHash,
            makePacket: { try self.session.fileRequestPacket(fileHash: $0) },
            onSent: { .fileRequestSent($0) },
            onFailed: { .fileRequestFailed(hash: $0, message: $1) },
            notReadyMessage: "File request requested before the peer connection became ready."
        )
    }

    @discardableResult
    public func sendSetRequestFileID(fileHash: Data) -> Bool {
        sendPeerFileCommand(
            fileHash: fileHash,
            makePacket: { try self.session.setRequestFileIDPacket(fileHash: $0) },
            onSent: { .setRequestFileIDSent($0) },
            onFailed: { .setRequestFileIDFailed(hash: $0, message: $1) },
            notReadyMessage: "Set request-file-id requested before the peer connection became ready."
        )
    }

    @discardableResult
    public func sendStartUploadRequest(fileHash: Data) -> Bool {
        sendPeerFileCommand(
            fileHash: fileHash,
            makePacket: { try self.session.startUploadRequestPacket(fileHash: $0) },
            onSent: { .startUploadRequestSent($0) },
            onFailed: { .startUploadRequestFailed(hash: $0, message: $1) },
            notReadyMessage: "Start-upload request requested before the peer connection became ready."
        )
    }

    @discardableResult
    public func sendSourceExchangeRequest(fileHash: Data) -> Bool {
        sendPeerFileCommand(
            fileHash: fileHash,
            makePacket: { try self.session.sourceExchangeRequestPacket(fileHash: $0) },
            onSent: { .sourceExchangeRequestSent($0) },
            onFailed: { .sourceExchangeRequestFailed(hash: $0, message: $1) },
            notReadyMessage: "Source exchange requested before the peer connection became ready."
        )
    }

    private func handleTransportState(_ state: ED2KPeerTCPTransportState) {
        switch state {
        case .ready:
            withStateLock {
                isReady = true
            }
            emit(.stateChanged(.connected))
            sendHello()
            transport.receiveNext()
        case .waiting:
            break
        case .failed(let message):
            withStateLock {
                isReady = false
            }
            emit(.stateChanged(.failed(message)))
        case .cancelled:
            withStateLock {
                isReady = false
            }
            emit(.stateChanged(.disconnected))
        }
    }

    private func sendHello() {
        do {
            let packet = try session.helloPacket()
            emit(.sessionEvent(.outgoingHello(packet)))
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(.helloSent)
                case .failed(let message):
                    self?.emit(.helloFailed(message))
                }
            }
        } catch {
            emit(.helloFailed(error.localizedDescription))
            transport.cancel()
        }
    }

    private func sendPeerFileCommand(
        fileHash: Data,
        makePacket: (Data) throws -> ED2KPacket,
        onSent: @escaping @Sendable (String) -> ED2KPeerTCPConnectionEvent,
        onFailed: @escaping @Sendable (String, String) -> ED2KPeerTCPConnectionEvent,
        notReadyMessage: String
    ) -> Bool {
        let hashText = fileHash.hexadecimalString

        guard withStateLock({ isReady }) else {
            emit(onFailed(hashText, notReadyMessage))
            return false
        }

        do {
            let packet = try makePacket(fileHash)
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(onSent(hashText))
                case .failed(let message):
                    self?.emit(onFailed(hashText, message))
                }
            }
            return true
        } catch {
            emit(onFailed(hashText, error.localizedDescription))
            return false
        }
    }

    private func handleReceivedData(_ data: Data) {
        do {
            for event in try session.receive(data) {
                emit(.sessionEvent(event))
            }
            transport.receiveNext()
        } catch {
            emit(.receiveFailed(error.localizedDescription))
            transport.cancel()
        }
    }

    private func emit(_ event: ED2KPeerTCPConnectionEvent) {
        eventHandler(event)
    }

    private func withStateLock<T>(_ work: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return work()
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

public final class NetworkED2KPeerTCPTransport: ED2KPeerTCPTransport, @unchecked Sendable {
    public var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)?
    public var receiveHandler: ((Data) -> Void)?

    private let connection: NWConnection

    public init(endpoint: ED2KPeerEndpoint, parameters: NWParameters = .tcp) {
        let host = NWEndpoint.Host(endpoint.host)
        let port = NWEndpoint.Port(rawValue: endpoint.port) ?? 4662
        connection = NWConnection(host: host, port: port, using: parameters)
    }

    public func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleNetworkState(state)
        }
        connection.start(queue: queue)
    }

    public func send(_ data: Data, completion: @escaping @Sendable (ED2KPeerTCPTransportSendResult) -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                completion(.failed(String(describing: error)))
            } else {
                completion(.sent)
            }
        })
    }

    public func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if let data, data.isEmpty == false {
                self?.receiveHandler?(data)
            }

            if let error {
                self?.stateUpdateHandler?(.failed(String(describing: error)))
            } else if isComplete {
                self?.stateUpdateHandler?(.cancelled)
            }
        }
    }

    public func cancel() {
        connection.cancel()
    }

    private func handleNetworkState(_ state: NWConnection.State) {
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
