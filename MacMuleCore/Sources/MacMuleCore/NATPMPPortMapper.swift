import Darwin
import Foundation
import SystemConfiguration

public final class SequentialPeerPortMapper: ED2KPeerPortMapper, @unchecked Sendable {
    private let mappers: [(name: String, mapper: ED2KPeerPortMapper)]

    public init(mappers: [(String, ED2KPeerPortMapper)]) {
        self.mappers = mappers.map { (name: $0.0, mapper: $0.1) }
    }

    public func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    ) {
        attemptMapping(
            at: 0,
            failures: [],
            tcpPort: tcpPort,
            udpPort: udpPort,
            completion: completion
        )
    }

    private func attemptMapping(
        at index: Int,
        failures: [String],
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    ) {
        guard index < mappers.count else {
            completion(
                UPnPPortMappingResult(
                    tcpMapped: false,
                    udpMapped: false,
                    detail: failures.joined(separator: " ")
                )
            )
            return
        }

        let mapperName = mappers[index].name
        let mapper = mappers[index].mapper
        mapper.ensureMappings(tcpPort: tcpPort, udpPort: udpPort) { result in
            if result.tcpMapped || result.udpMapped {
                let detailPrefix = failures.isEmpty ? "" : failures.joined(separator: " ") + " "
                completion(
                    UPnPPortMappingResult(
                        tcpMapped: result.tcpMapped,
                        udpMapped: result.udpMapped,
                        detail: detailPrefix + "\(mapperName): \(result.detail)"
                    )
                )
                return
            }

            self.attemptMapping(
                at: index + 1,
                failures: failures + ["\(mapperName): \(result.detail)"],
                tcpPort: tcpPort,
                udpPort: udpPort,
                completion: completion
            )
        }
    }
}

public final class NATPMPPortMapper: ED2KPeerPortMapper, @unchecked Sendable {
    private struct PortSet: Equatable {
        var tcpPort: UInt16
        var udpPort: UInt16
    }

    private let queue = DispatchQueue(label: "MacMule.NATPMPPortMapper")
    private let timeout: TimeInterval
    private let gatewayProvider: @Sendable () -> String?
    private let leaseDuration: UInt32
    private var isMappingInFlight = false
    private var lastMappedPorts: PortSet?

    public init(
        timeout: TimeInterval = 2.0,
        leaseDuration: UInt32 = 3600,
        gatewayProvider: (@Sendable () -> String?)? = nil
    ) {
        self.timeout = timeout
        self.leaseDuration = leaseDuration
        self.gatewayProvider = gatewayProvider ?? NATPMPPortMapper.defaultGatewayIPv4Address
    }

    public func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    ) {
        let ports = PortSet(tcpPort: tcpPort, udpPort: udpPort)

        queue.async { [weak self] in
            guard let self else { return }
            guard self.isMappingInFlight == false else {
                completion(
                    UPnPPortMappingResult(
                        tcpMapped: false,
                        udpMapped: false,
                        detail: "Ya hay una negociacion NAT-PMP en curso."
                    )
                )
                return
            }

            guard self.lastMappedPorts != ports else {
                completion(
                    UPnPPortMappingResult(
                        tcpMapped: true,
                        udpMapped: true,
                        detail: "Los puertos ya estaban publicados por NAT-PMP."
                    )
                )
                return
            }

            self.isMappingInFlight = true
            let result = self.performMapping(tcpPort: tcpPort, udpPort: udpPort)
            if result.tcpMapped || result.udpMapped {
                self.lastMappedPorts = ports
            }
            self.isMappingInFlight = false
            completion(result)
        }
    }

    private func performMapping(tcpPort: UInt16, udpPort: UInt16) -> UPnPPortMappingResult {
        guard let gatewayAddress = gatewayProvider() else {
            return UPnPPortMappingResult(
                tcpMapped: false,
                udpMapped: false,
                detail: "No se pudo resolver la puerta de enlace local para NAT-PMP."
            )
        }

        var tcpMapped = false
        var udpMapped = false
        var details: [String] = []

        do {
            let response = try requestMapping(
                gatewayAddress: gatewayAddress,
                protocolOpcode: 1,
                internalPort: tcpPort,
                requestedExternalPort: tcpPort,
                lifetime: leaseDuration
            )
            tcpMapped = true
            details.append("NAT-PMP publico TCP :\(tcpPort) como :\(response.externalPort) en \(gatewayAddress).")
        } catch {
            details.append("NAT-PMP TCP fallo: \(error.localizedDescription)")
        }

        do {
            let response = try requestMapping(
                gatewayAddress: gatewayAddress,
                protocolOpcode: 2,
                internalPort: udpPort,
                requestedExternalPort: udpPort,
                lifetime: leaseDuration
            )
            udpMapped = true
            details.append("NAT-PMP publico UDP :\(udpPort) como :\(response.externalPort) en \(gatewayAddress).")
        } catch {
            details.append("NAT-PMP UDP fallo: \(error.localizedDescription)")
        }

        return UPnPPortMappingResult(
            tcpMapped: tcpMapped,
            udpMapped: udpMapped,
            detail: details.joined(separator: " ")
        )
    }

    private func requestMapping(
        gatewayAddress: String,
        protocolOpcode: UInt8,
        internalPort: UInt16,
        requestedExternalPort: UInt16,
        lifetime: UInt32
    ) throws -> NATPMPMappingResponse {
        let request = Self.makeMappingRequest(
            protocolOpcode: protocolOpcode,
            internalPort: internalPort,
            requestedExternalPort: requestedExternalPort,
            lifetime: lifetime
        )
        let responseData = try sendRequest(
            request,
            gatewayAddress: gatewayAddress
        )
        let response = try Self.parseMappingResponse(
            responseData,
            expectedOpcode: protocolOpcode
        )
        guard response.resultCode == .success else {
            throw NATPMPPortMapperError.gatewayRejected(
                code: response.resultCode.rawValue
            )
        }
        return response
    }

    private func sendRequest(_ request: Data, gatewayAddress: String) throws -> Data {
        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fileDescriptor >= 0 else {
            throw NATPMPPortMapperError.socketCreationFailed
        }
        defer { close(fileDescriptor) }

        var timeoutValue = timeval(
            tv_sec: Int(timeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeoutValue,
            socklen_t(MemoryLayout<timeval>.size)
        )
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeoutValue,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(5351).bigEndian
        let parseResult = gatewayAddress.withCString { sourcePointer in
            inet_pton(AF_INET, sourcePointer, &destination.sin_addr)
        }
        guard parseResult == 1 else {
            throw NATPMPPortMapperError.invalidGatewayAddress(gatewayAddress)
        }

        let sendResult = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                request.withUnsafeBytes { rawBuffer in
                    sendto(
                        fileDescriptor,
                        rawBuffer.baseAddress,
                        rawBuffer.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.stride)
                    )
                }
            }
        }
        guard sendResult >= 0 else {
            throw NATPMPPortMapperError.sendFailed(errno)
        }

        var buffer = [UInt8](repeating: 0, count: 32)
        let bytesRead = recv(fileDescriptor, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            throw NATPMPPortMapperError.receiveFailed(errno)
        }

        return Data(buffer.prefix(bytesRead))
    }

    static func makeMappingRequest(
        protocolOpcode: UInt8,
        internalPort: UInt16,
        requestedExternalPort: UInt16,
        lifetime: UInt32
    ) -> Data {
        var request = Data()
        request.append(0)
        request.append(protocolOpcode)
        request.appendUInt16BigEndian(0)
        request.appendUInt16BigEndian(internalPort)
        request.appendUInt16BigEndian(requestedExternalPort)
        request.appendUInt32BigEndian(lifetime)
        return request
    }

    static func parseMappingResponse(
        _ data: Data,
        expectedOpcode: UInt8
    ) throws -> NATPMPMappingResponse {
        guard data.count >= 16 else {
            throw NATPMPPortMapperError.invalidResponse("La respuesta NAT-PMP era demasiado corta.")
        }

        let version = data[0]
        guard version == 0 else {
            throw NATPMPPortMapperError.invalidResponse("La puerta de enlace NAT-PMP devolvio una version no soportada: \(version).")
        }

        let opcode = data[1]
        guard opcode == expectedOpcode | 0x80 else {
            throw NATPMPPortMapperError.invalidResponse("El opcode NAT-PMP de respuesta no coincide con la peticion.")
        }

        let resultCode = NATPMPResultCode(rawValue: data.readUInt16BigEndian(at: 2)) ?? .unsupportedOpcode
        return NATPMPMappingResponse(
            protocolOpcode: expectedOpcode,
            resultCode: resultCode,
            epoch: data.readUInt32BigEndian(at: 4),
            internalPort: data.readUInt16BigEndian(at: 8),
            externalPort: data.readUInt16BigEndian(at: 10),
            lifetime: data.readUInt32BigEndian(at: 12)
        )
    }

    public static func defaultGatewayIPv4Address() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MacMule.NATPMPPortMapper" as CFString, nil, nil) else {
            return nil
        }

        let key = "State:/Network/Global/IPv4" as CFString
        guard let value = SCDynamicStoreCopyValue(store, key),
              let dictionary = value as? [String: Any] else {
            return nil
        }
        return dictionary["Router"] as? String
    }
}

struct NATPMPMappingResponse: Equatable, Sendable {
    var protocolOpcode: UInt8
    var resultCode: NATPMPResultCode
    var epoch: UInt32
    var internalPort: UInt16
    var externalPort: UInt16
    var lifetime: UInt32
}

enum NATPMPResultCode: UInt16, Equatable, Sendable {
    case success = 0
    case unsupportedVersion = 1
    case notAuthorized = 2
    case networkFailure = 3
    case outOfResources = 4
    case unsupportedOpcode = 5
}

enum NATPMPPortMapperError: LocalizedError {
    case socketCreationFailed
    case invalidGatewayAddress(String)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case invalidResponse(String)
    case gatewayRejected(code: UInt16)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed:
            return "No se pudo crear el socket UDP para NAT-PMP."
        case .invalidGatewayAddress(let address):
            return "La puerta de enlace NAT-PMP no tenia una direccion IPv4 valida: \(address)."
        case .sendFailed(let code):
            return "No se pudo enviar la peticion NAT-PMP al router (errno \(code))."
        case .receiveFailed(let code):
            if code == 0 {
                return "La puerta de enlace NAT-PMP no respondio a tiempo."
            }
            return "No se pudo leer la respuesta NAT-PMP del router (errno \(code))."
        case .invalidResponse(let detail):
            return "La respuesta NAT-PMP del router no era valida: \(detail)"
        case .gatewayRejected(let code):
            return "La puerta de enlace NAT-PMP rechazo el mapeo con codigo \(code)."
        }
    }
}

private extension Data {
    mutating func appendUInt16BigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0x00FF))
        append(UInt8(value & 0x00FF))
    }

    mutating func appendUInt32BigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8(value & 0x000000FF))
    }

    func readUInt16BigEndian(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func readUInt32BigEndian(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 |
        UInt32(self[offset + 1]) << 16 |
        UInt32(self[offset + 2]) << 8 |
        UInt32(self[offset + 3])
    }
}
