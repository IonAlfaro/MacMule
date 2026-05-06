import Foundation
import Network

public enum ED2KServerTCPConnectionState: Equatable, Sendable {
    case connecting
    case waiting(String)
    case connected
    case disconnected
    case failed(String)
}

public enum ED2KServerTCPConnectionEvent: Equatable, Sendable {
    case stateChanged(ED2KServerTCPConnectionState)
    case sessionEvent(ED2KServerSessionEvent)
    case loginSent
    case loginFailed(String)
    case emptyOfferFilesSent
    case emptyOfferFilesFailed(String)
    case offerFilesSent
    case offerFilesFailed(String)
    case searchSent(String)
    case searchFailed(query: String, message: String)
    case sourceLookupSent(String)
    case sourceLookupFailed(hash: String, message: String)
    case callbackRequestSent(UInt32)
    case callbackRequestFailed(UInt32, String)
    case receiveFailed(String)
}

public enum ED2KServerTCPTransportState: Equatable, Sendable {
    case ready
    case waiting(String)
    case failed(String)
    case cancelled
}

public enum ED2KServerTCPTransportSendResult: Equatable, Sendable {
    case sent
    case failed(String)
}

public protocol ED2KServerTCPTransport: AnyObject {
    var stateUpdateHandler: ((ED2KServerTCPTransportState) -> Void)? { get set }
    var receiveHandler: ((Data) -> Void)? { get set }
    var logHandler: (@Sendable (String) -> Void)? { get set }

    func start(queue: DispatchQueue)
    func send(_ data: Data, completion: @escaping @Sendable (ED2KServerTCPTransportSendResult) -> Void)
    func receiveNext()
    func cancel()
}

public final class ED2KServerTCPConnection: @unchecked Sendable {
    public let configuration: ED2KServerSessionConfiguration

    private var session: ED2KServerSession
    private let transport: ED2KServerTCPTransport
    private let queue: DispatchQueue
    private let eventHandler: (ED2KServerTCPConnectionEvent) -> Void
    private let stateLock = NSLock()
    private var isReady = false
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private static let connectionTimeout: TimeInterval = 30

    public convenience init(
        configuration: ED2KServerSessionConfiguration,
        queue: DispatchQueue = DispatchQueue(label: "MacMule.ED2KServerTCPConnection"),
        eventHandler: @escaping (ED2KServerTCPConnectionEvent) -> Void
    ) {
        self.init(
            configuration: configuration,
            transport: NetworkED2KServerTCPTransport(endpoint: configuration.endpoint),
            queue: queue,
            eventHandler: eventHandler
        )
    }

    public init(
        configuration: ED2KServerSessionConfiguration,
        transport: ED2KServerTCPTransport,
        queue: DispatchQueue = DispatchQueue(label: "MacMule.ED2KServerTCPConnection"),
        eventHandler: @escaping (ED2KServerTCPConnectionEvent) -> Void
    ) {
        self.configuration = configuration
        session = ED2KServerSession(configuration: configuration)
        self.transport = transport
        self.queue = queue
        self.eventHandler = eventHandler
    }

    public func start() {
        emit(.stateChanged(.connecting))
        scheduleConnectionTimeout()

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
            connectionTimeoutWorkItem?.cancel()
            connectionTimeoutWorkItem = nil
        }
        transport.cancel()
    }

    @discardableResult
    public func sendEmptyOfferFiles() -> Bool {
        guard withStateLock({ isReady }) else {
            emit(.emptyOfferFilesFailed("OfferFiles requested before the eD2k server connection became ready."))
            return false
        }

        let packet = session.emptyOfferFilesPacket()
        transport.send(packet.encoded()) { [weak self] result in
            switch result {
            case .sent:
                self?.emit(.emptyOfferFilesSent)
            case .failed(let message):
                self?.emit(.emptyOfferFilesFailed(message))
            }
        }
        return true
    }

    @discardableResult
    public func sendOfferFiles(fileHashes: [Data]) -> Bool {
        guard withStateLock({ isReady }) else {
            emit(.offerFilesFailed("OfferFiles requested before the eD2k server connection became ready."))
            return false
        }

        let packet = session.offerFilesPacket(fileHashes: fileHashes)
        transport.send(packet.encoded()) { [weak self] result in
            switch result {
            case .sent:
                self?.emit(.offerFilesSent)
            case .failed(let message):
                self?.emit(.offerFilesFailed(message))
            }
        }
        return true
    }

    @discardableResult
    public func sendSearch(query: String) -> Bool {
        guard withStateLock({ isReady }) else {
            emit(.searchFailed(query: query, message: "Search requested before the eD2k server connection became ready."))
            return false
        }

        do {
            let packet = try session.searchPacket(query: query)
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(.searchSent(query))
                case .failed(let message):
                    self?.emit(.searchFailed(query: query, message: message))
                }
            }
            return true
        } catch {
            emit(.searchFailed(query: query, message: error.localizedDescription))
            return false
        }
    }

    @discardableResult
    public func sendSourceLookup(fileHash: Data, fileSizeInBytes: UInt64) -> Bool {
        let hashText = fileHash.hexadecimalString

        guard withStateLock({ isReady }) else {
            emit(.sourceLookupFailed(hash: hashText, message: "Source lookup requested before the eD2k server connection became ready."))
            return false
        }

        do {
            let packet = try session.sourceRequestPacket(fileHash: fileHash, fileSizeInBytes: fileSizeInBytes)
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(.sourceLookupSent(hashText))
                case .failed(let message):
                    self?.emit(.sourceLookupFailed(hash: hashText, message: message))
                }
            }
            return true
        } catch {
            emit(.sourceLookupFailed(hash: hashText, message: error.localizedDescription))
            return false
        }
    }

    @discardableResult
    public func sendCallbackRequest(clientID: UInt32) -> Bool {
        guard withStateLock({ isReady }) else {
            emit(.callbackRequestFailed(clientID, "Callback requested before the eD2k server connection became ready."))
            return false
        }

        let packet = session.callbackRequestPacket(clientID: clientID)
        transport.send(packet.encoded()) { [weak self] result in
            switch result {
            case .sent:
                self?.emit(.callbackRequestSent(clientID))
            case .failed(let message):
                self?.emit(.callbackRequestFailed(clientID, message))
            }
        }
        return true
    }

    private func handleTransportState(_ state: ED2KServerTCPTransportState) {
        switch state {
        case .ready:
            withStateLock {
                isReady = true
                connectionTimeoutWorkItem?.cancel()
                connectionTimeoutWorkItem = nil
            }
            emit(.stateChanged(.connected))
            sendLogin()
            transport.receiveNext()
        case .waiting(let message):
            emit(.stateChanged(.waiting(message)))
        case .failed(let message):
            withStateLock {
                isReady = false
                connectionTimeoutWorkItem?.cancel()
                connectionTimeoutWorkItem = nil
            }
            emit(.stateChanged(.failed(message)))
        case .cancelled:
            withStateLock {
                isReady = false
                connectionTimeoutWorkItem?.cancel()
                connectionTimeoutWorkItem = nil
            }
            emit(.stateChanged(.disconnected))
        }
    }

    private func scheduleConnectionTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let shouldFail = self.withStateLock { () -> Bool in
                if self.isReady {
                    return false
                }
                self.connectionTimeoutWorkItem = nil
                return true
            }
            guard shouldFail else { return }
            self.emit(.stateChanged(.failed("Timed out connecting to the eD2k server.")))
            self.transport.cancel()
        }

        withStateLock {
            connectionTimeoutWorkItem?.cancel()
            connectionTimeoutWorkItem = workItem
        }

        queue.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: workItem)
    }

    private func sendLogin() {
        do {
            let packet = try session.loginPacket()
            emit(.sessionEvent(.outgoingLogin(packet)))
            transport.send(packet.encoded()) { [weak self] result in
                switch result {
                case .sent:
                    self?.emit(.loginSent)
                case .failed(let message):
                    self?.emit(.loginFailed(message))
                }
            }
        } catch {
            emit(.loginFailed(error.localizedDescription))
            transport.cancel()
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

    private func emit(_ event: ED2KServerTCPConnectionEvent) {
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

public final class NetworkED2KServerTCPTransport: ED2KServerTCPTransport, @unchecked Sendable {
    public var stateUpdateHandler: ((ED2KServerTCPTransportState) -> Void)?
    public var receiveHandler: ((Data) -> Void)?
    public var logHandler: (@Sendable (String) -> Void)?

    private let connection: NWConnection
    private let endpoint: ED2KServerEndpoint

    public init(endpoint: ED2KServerEndpoint, parameters: NWParameters = .tcp) {
        self.endpoint = endpoint
        let host = NWEndpoint.Host(endpoint.host)
        let port = NWEndpoint.Port(rawValue: endpoint.port) ?? 4661
        connection = NWConnection(host: host, port: port, using: parameters)
        logHandler?("[eD2k] Transport created for \(endpoint.host):\(endpoint.port)")
    }

    public func start(queue: DispatchQueue) {
        logHandler?("[eD2k] Transport start requested for \(endpoint.host):\(endpoint.port)")
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleNetworkState(state)
        }
        connection.start(queue: queue)
        logHandler?("[eD2k] NWConnection.start() called")
    }

    public func send(_ data: Data, completion: @escaping @Sendable (ED2KServerTCPTransportSendResult) -> Void) {
        logHandler?("[eD2k] Sending \(data.count) bytes to \(endpoint.host):\(endpoint.port)")
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error {
                let msg = nwErrorDescription(error)
                self.logHandler?("[eD2k] Send failed: \(msg)")
                completion(.failed(msg))
            } else {
                self.logHandler?("[eD2k] Sent \(data.count) bytes successfully")
                completion(.sent)
            }
        })
    }

    public func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data, data.isEmpty == false {
                self.logHandler?("[eD2k] Received \(data.count) bytes from \(self.endpoint.host)")
                self.receiveHandler?(data)
            }

            if let error {
                let msg = nwErrorDescription(error)
                self.logHandler?("[eD2k] Receive error: \(msg)")
                self.stateUpdateHandler?(.failed(msg))
            } else if isComplete {
                self.logHandler?("[eD2k] Connection closed by server")
                self.stateUpdateHandler?(.cancelled)
            } else {
                self.receiveNext()
            }
        }
    }

    private func handleNetworkState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            logHandler?("[eD2k] NWConnection READY for \(endpoint.host):\(endpoint.port)")
            stateUpdateHandler?(.ready)
        case .waiting(let error):
            let msg = nwErrorDescription(error)
            logHandler?("[eD2k] NWConnection WAITING: \(msg)")
            stateUpdateHandler?(.waiting(msg))
        case .failed(let error):
            let msg = nwErrorDescription(error)
            logHandler?("[eD2k] NWConnection FAILED: \(msg)")
            stateUpdateHandler?(.failed(msg))
        case .cancelled:
            logHandler?("[eD2k] NWConnection cancelled")
            stateUpdateHandler?(.cancelled)
        case .setup:
            logHandler?("[eD2k] NWConnection setup")
            break
        case .preparing:
            logHandler?("[eD2k] NWConnection preparing...")
            stateUpdateHandler?(.waiting("Preparing connection..."))
        @unknown default:
            let stateDesc = String(describing: state)
            logHandler?("[eD2k] NWConnection unknown state: \(stateDesc)")
            break
        }
    }

    public func cancel() {
        connection.cancel()
    }
}

private func nwErrorDescription(_ error: NWError) -> String {
    switch error {
    case .posix(let code):
        switch code {
        case .ECONNREFUSED: return "Connection refused by server"
        case .ETIMEDOUT: return "Connection timed out"
        case .ENETUNREACH: return "Network unreachable"
        case .EHOSTUNREACH: return "Host unreachable"
        case .ECONNRESET: return "Connection reset by server"
        case .ENETDOWN: return "Network down"
        case .EADDRNOTAVAIL: return "Address not available"
        case .EACCES: return "Permission denied"
        case .EPERM: return "Operation not permitted"
        case .ENOTCONN: return "Not connected"
        case .ESHUTDOWN: return "Connection closed"
        default:
            if code.rawValue == 81 {
                return "Network authentication error"
            }
            return "Connection error (code \(code.rawValue))"
        }
    case .dns(let code):
        return "DNS error (code \(code))"
    case .tls(let code):
        return "TLS error (code \(code))"
    @unknown default:
        return "Unknown network error"
    }
}

private extension ED2KServerTCPConnection {
    /// Deprecated — this code won't be reached if NWConnection path is used.
    private func handleNetworkState(_ state: NWConnection.State) {
        // kept for backward compat — actual implementation moved inside NetworkED2KServerTCPTransport
    }
}
