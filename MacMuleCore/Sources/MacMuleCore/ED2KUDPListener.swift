import Foundation
import Network

public final class ED2KUDPListener: @unchecked Sendable {
    public private(set) var isListening = false
    public private(set) var boundPort: UInt16 = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.macmule.ed2k.udp", qos: .utility)
    private let logHandler: (@Sendable (String) -> Void)?

    public init(logHandler: (@Sendable (String) -> Void)? = nil) {
        self.logHandler = logHandler
    }

    public func start(port: UInt16) throws {
        guard !isListening else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ED2KUDPError.invalidPort(port)
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: nwPort)
        listener?.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                self?.log("eD2k UDP listener ready on port \(port)")
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            connection.receiveMessage { data, _, _, _ in
                // eD2k UDP responses come back here
                connection.cancel()
            }
        }
        listener?.start(queue: queue)
        isListening = true
        boundPort = port
    }

    public func stop() {
        guard isListening else { return }
        isListening = false
        listener?.cancel()
        listener = nil
        boundPort = 0
    }

    public func sendServerStatusRequest(host: String, port: UInt16) {
        var packet = Data()
        packet.append(UInt8(0xE3))
        packet.append(UInt8(0x96)) // OP_SERVERSTATUS

        sendUDPPacket(packet, to: host, port: port) { _ in }
    }

    public func sendSourceLookupRequest(fileHash: Data, host: String, port: UInt16) {
        var packet = Data()
        packet.append(UInt8(0xE3))
        packet.append(UInt8(0x9A)) // OP_GLOBGETSOURCES
        packet.append(fileHash)

        sendUDPPacket(packet, to: host, port: port) { _ in }
    }

    public func sendCallbackRequest(clientID: UInt32, host: String, port: UInt16) {
        var packet = Data()
        packet.append(UInt8(0xE3))
        packet.append(UInt8(0x9C)) // OP_GLOBCALLBACKREQ

        var id = clientID.littleEndian
        withUnsafeBytes(of: &id) { packet.append(Data($0)) }

        sendUDPPacket(packet, to: host, port: port) { _ in }
    }

    public func sendSearchRequest(query: String, host: String, port: UInt16) {
        var packet = Data()
        packet.append(UInt8(0xE3))
        packet.append(UInt8(0x98)) // OP_GLOBSEARCHREQ

        var queryLen = UInt16(query.utf8.count).littleEndian
        withUnsafeBytes(of: &queryLen) { packet.append(Data($0)) }
        packet.append(Data(query.utf8))

        sendUDPPacket(packet, to: host, port: port) { _ in }
    }

    private func sendUDPPacket(_ data: Data, to host: String, port: UInt16, completion: @escaping (Data?) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            log("eD2k UDP: invalid port for \(host):\(port)")
            completion(nil)
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: queue)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.log("eD2k UDP send error to \(host):\(port): \(error)")
                completion(nil)
            } else {
                // Try to receive response
                connection.receiveMessage { data, _, _, _ in
                    completion(data)
                    connection.cancel()
                }
            }
        })
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}

public enum ED2KUDPError: Error, Equatable, LocalizedError {
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid eD2k UDP port: \(port)."
        }
    }
}
