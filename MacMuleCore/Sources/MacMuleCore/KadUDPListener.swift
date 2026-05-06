import Foundation
import Network

public protocol KadUDPPacketHandler: AnyObject, Sendable {
    func handleKadPacket(_ data: Data, from endpoint: KadEndpoint)
}

public final class KadUDPListener: @unchecked Sendable {
    public private(set) var isListening: Bool = false
    public private(set) var boundPort: UInt16 = 0
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.macmule.kad.udp", qos: .utility)
    private let logHandler: (@Sendable (String) -> Void)?
    private let packetHandlerLock = NSLock()
    private weak var _packetHandler: (any KadUDPPacketHandler)?

    public init(logHandler: (@Sendable (String) -> Void)? = nil) {
        self.logHandler = logHandler
    }

    public func setPacketHandler(_ handler: any KadUDPPacketHandler) {
        packetHandlerLock.lock()
        _packetHandler = handler
        packetHandlerLock.unlock()
    }
    
    private var packetHandler: (any KadUDPPacketHandler)? {
        packetHandlerLock.lock()
        defer { packetHandlerLock.unlock() }
        return _packetHandler
    }

    public func start(port: UInt16) throws {
        guard !isListening else { return }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw KadListenerError.invalidPort(port)
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: nwPort)
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state)
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener?.start(queue: queue)
        isListening = true
        boundPort = port
        log("Kad UDP listener started on port \(port)")
    }

    public func stop() {
        guard isListening else { return }
        isListening = false
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        boundPort = 0
        log("Kad UDP listener stopped")
    }

    public func sendPacket(_ data: Data, to endpoint: KadEndpoint) {
        guard isListening, let listener = listener else {
            log("Kad: cannot send — not listening")
            return
        }

        guard let nwPort = NWEndpoint.Port(rawValue: endpoint.port) else {
            log("Kad: invalid endpoint port \(endpoint.port)")
            return
        }

        let host = NWEndpoint.Host(endpoint.ipAddress)
        let dest = NWEndpoint.hostPort(host: host, port: nwPort)
        let connection = NWConnection(to: dest, using: .udp)
        connection.start(queue: queue)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.log("Kad send error to \(endpoint.ipAddress):\(endpoint.port): \(error)")
            }
            connection.cancel()
        })
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, self.isListening else { return }

            if let error = error {
                self.log("Kad receive error: \(error)")
                return
            }

            if let data = data {
                let senderEndpoint: KadEndpoint
                let remoteEndpoint = connection.endpoint
                senderEndpoint = self.extractEndpoint(from: remoteEndpoint)
                self.packetHandler?.handleKadPacket(data, from: senderEndpoint)
            }
            connection.cancel()
        }
    }

    private func extractEndpoint(from endpoint: NWEndpoint) -> KadEndpoint {
        switch endpoint {
        case .hostPort(let host, let port):
            return KadEndpoint(
                ipAddress: "\(host)",
                port: port.rawValue
            )
        default:
            return KadEndpoint(ipAddress: "0.0.0.0", port: 0)
        }
    }

    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            log("Kad UDP listener ready on port \(boundPort)")
        case .failed(let error):
            log("Kad UDP listener failed: \(error)")
            isListening = false
        case .cancelled:
            log("Kad UDP listener cancelled")
            isListening = false
        default:
            break
        }
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}

public enum KadListenerError: Error, Equatable, LocalizedError {
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid Kad UDP port: \(port)."
        }
    }
}
