import Darwin
import Foundation

public struct UPnPPortMappingResult: Equatable, Sendable {
    public var tcpMapped: Bool
    public var udpMapped: Bool
    public var detail: String

    public init(tcpMapped: Bool, udpMapped: Bool, detail: String) {
        self.tcpMapped = tcpMapped
        self.udpMapped = udpMapped
        self.detail = detail
    }
}

public protocol ED2KPeerPortMapper: AnyObject {
    func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    )
}

public final class UPnPPortMapper: ED2KPeerPortMapper, @unchecked Sendable {
    private struct PortSet: Equatable {
        var tcpPort: UInt16
        var udpPort: UInt16
    }

    private let queue = DispatchQueue(label: "MacMule.UPnPPortMapper")
    private let session: URLSession
    private var isMappingInFlight = false
    private var lastMappedPorts: PortSet?

    public init(session: URLSession = .shared) {
        self.session = session
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
                        detail: "Ya hay una negociacion UPnP en curso."
                    )
                )
                return
            }

            guard self.lastMappedPorts != ports else {
                completion(
                    UPnPPortMappingResult(
                        tcpMapped: true,
                        udpMapped: true,
                        detail: "Los puertos ya estaban publicados por UPnP."
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
        do {
            guard let localAddress = Self.preferredLocalIPv4Address() else {
                return UPnPPortMappingResult(
                    tcpMapped: false,
                    udpMapped: false,
                    detail: "Could not resolve local IP for mapping."
                )
            }

            let discoveredServices = try Self.discoverInternetGatewayServices(timeout: 2.0)
            guard discoveredServices.isEmpty == false else {
                return UPnPPortMappingResult(
                    tcpMapped: false,
                    udpMapped: false,
                    detail: "No se encontro un router UPnP/IGD en la red local."
                )
            }

            var lastError = "El router anuncio UPnP, pero no acepto el mapeo."
            for service in discoveredServices {
                do {
                    let tcpMapped = try addPortMapping(
                        using: service,
                        externalPort: tcpPort,
                        internalPort: tcpPort,
                        protocolName: "TCP",
                        internalClient: localAddress
                    )
                    let udpMapped = try addPortMapping(
                        using: service,
                        externalPort: udpPort,
                        internalPort: udpPort,
                        protocolName: "UDP",
                        internalClient: localAddress
                    )
                    let detail = "UPnP publico TCP :\(tcpPort) y UDP :\(udpPort) hacia \(localAddress)."
                    return UPnPPortMappingResult(
                        tcpMapped: tcpMapped,
                        udpMapped: udpMapped,
                        detail: detail
                    )
                } catch {
                    lastError = error.localizedDescription
                }
            }

            return UPnPPortMappingResult(
                tcpMapped: false,
                udpMapped: false,
                detail: lastError
            )
        } catch {
            return UPnPPortMappingResult(
                tcpMapped: false,
                udpMapped: false,
                detail: error.localizedDescription
            )
        }
    }

    private func addPortMapping(
        using service: UPnPInternetGatewayService,
        externalPort: UInt16,
        internalPort: UInt16,
        protocolName: String,
        internalClient: String
    ) throws -> Bool {
        let soapEnvelope = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:AddPortMapping xmlns:u="\(service.serviceType)">
              <NewRemoteHost></NewRemoteHost>
              <NewExternalPort>\(externalPort)</NewExternalPort>
              <NewProtocol>\(protocolName)</NewProtocol>
              <NewInternalPort>\(internalPort)</NewInternalPort>
              <NewInternalClient>\(Self.xmlEscaped(internalClient))</NewInternalClient>
              <NewEnabled>1</NewEnabled>
              <NewPortMappingDescription>MacMule</NewPortMappingDescription>
              <NewLeaseDuration>0</NewLeaseDuration>
            </u:AddPortMapping>
          </s:Body>
        </s:Envelope>
        """

        var request = URLRequest(url: service.controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.serviceType)#AddPortMapping\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(soapEnvelope.utf8)

        let (data, response) = try synchronousData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UPnPPortMapperError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return true
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        if responseBody.contains("<errorCode>718</errorCode>") {
            return true
        }

        throw UPnPPortMapperError.soapFailure(code: httpResponse.statusCode, detail: responseBody)
    }

    private func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronizedBox<Result<(Data, URLResponse), Error>>()

        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                resultBox.value = .failure(error)
                return
            }
            guard let data, let response else {
                resultBox.value = .failure(UPnPPortMapperError.invalidResponse)
                return
            }
            resultBox.value = .success((data, response))
        }.resume()

        _ = semaphore.wait(timeout: .now() + 5)
        guard let result = resultBox.value else {
            throw UPnPPortMapperError.timeout
        }
        return try result.get()
    }

    static func discoverInternetGatewayServices(timeout: TimeInterval) throws -> [UPnPInternetGatewayService] {
        let locations = try discoverDescriptionLocations(timeout: timeout)
        var services: [UPnPInternetGatewayService] = []
        var seen = Set<URL>()

        for location in locations {
            guard let service = try parseInternetGatewayService(from: location) else {
                continue
            }
            guard seen.insert(service.controlURL).inserted else {
                continue
            }
            services.append(service)
        }

        return services
    }

    static func parseInternetGatewayService(from descriptionURL: URL) throws -> UPnPInternetGatewayService? {
        let session = URLSession.shared
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronizedBox<Result<Data, Error>>()

        session.dataTask(with: descriptionURL) { data, _, error in
            defer { semaphore.signal() }
            if let error {
                resultBox.value = .failure(error)
            } else if let data {
                resultBox.value = .success(data)
            } else {
                resultBox.value = .failure(UPnPPortMapperError.invalidResponse)
            }
        }.resume()

        _ = semaphore.wait(timeout: .now() + 5)
        guard let result = resultBox.value else {
            throw UPnPPortMapperError.timeout
        }

        let data = try result.get()
        let parser = UPnPDeviceDescriptionParser()
        return try parser.parse(data: data, descriptionURL: descriptionURL)
    }

    static func preferredLocalIPv4Address() -> String? {
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacePointer) == 0, let first = interfacePointer else {
            return nil
        }
        defer { freeifaddrs(interfacePointer) }

        var candidates: [(name: String, address: String)] = []
        var pointer = first

        while true {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else {
                if let next = interface.ifa_next {
                    pointer = next
                    continue
                }
                break
            }

            let family = Int32(address.pointee.sa_family)
            let flags = Int32(interface.ifa_flags)
            if family == AF_INET,
               (flags & IFF_UP) != 0,
               (flags & IFF_LOOPBACK) == 0 {
                let name = String(cString: interface.ifa_name)
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let host: String
                    if let baseAddress = hostBuffer.withUnsafeBufferPointer(\.baseAddress) {
                        host = String(validatingCString: baseAddress) ?? ""
                    } else {
                        host = ""
                    }
                    candidates.append((name: name, address: host))
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        if let preferred = candidates.first(where: { $0.name.hasPrefix("en") }) {
            return preferred.address
        }

        return candidates.first?.address
    }

    private static func discoverDescriptionLocations(timeout: TimeInterval) throws -> [URL] {
        let searchTargets = [
            "urn:schemas-upnp-org:service:WANIPConnection:1",
            "urn:schemas-upnp-org:service:WANIPConnection:2",
            "urn:schemas-upnp-org:service:WANPPPConnection:1",
            "urn:schemas-upnp-org:service:WANPPPConnection:2"
        ]

        var discovered: [URL] = []
        var seen = Set<URL>()

        for searchTarget in searchTargets {
            for url in try sendDiscoveryRequest(searchTarget: searchTarget, timeout: timeout) {
                guard seen.insert(url).inserted else {
                    continue
                }
                discovered.append(url)
            }
        }

        return discovered
    }

    private static func sendDiscoveryRequest(searchTarget: String, timeout: TimeInterval) throws -> [URL] {
        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fileDescriptor >= 0 else {
            throw UPnPPortMapperError.socketCreationFailed
        }
        defer { close(fileDescriptor) }

        var receiveTimeout = timeval(
            tv_sec: Int(timeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var reuseAddress: Int32 = 1
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        destination.sin_addr = in_addr(s_addr: inet_addr("239.255.255.250"))

        let payload = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: \(searchTarget)\r
        \r
        """

        let payloadBytes = Array(payload.utf8)
        let sendResult = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                payloadBytes.withUnsafeBytes { rawBuffer in
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
            throw UPnPPortMapperError.discoverySendFailed
        }

        var urls: [URL] = []
        var seen = Set<URL>()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(fileDescriptor, &buffer, buffer.count, 0)
            if bytesRead <= 0 {
                break
            }

            let response = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
            guard let location = locationHeader(from: response),
                  let url = URL(string: location),
                  seen.insert(url).inserted else {
                continue
            }
            urls.append(url)
        }

        return urls
    }

    private static func locationHeader(from response: String) -> String? {
        for line in response.split(whereSeparator: \.isNewline) {
            let rawLine = String(line)
            guard rawLine.lowercased().hasPrefix("location:") else {
                continue
            }
            return rawLine.dropFirst("location:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

struct UPnPInternetGatewayService: Equatable, Sendable {
    var serviceType: String
    var controlURL: URL
}

enum UPnPPortMapperError: LocalizedError {
    case socketCreationFailed
    case discoverySendFailed
    case invalidResponse
    case timeout
    case soapFailure(code: Int, detail: String)
    case invalidDescription(String)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed:
            return "Could not create SSDP socket for UPnP."
        case .discoverySendFailed:
            return "No se pudo enviar la peticion SSDP a la red local."
        case .invalidResponse:
            return "La respuesta del router UPnP no era valida."
        case .timeout:
            return "La negociacion UPnP agoto el tiempo de espera."
        case .soapFailure(let code, let detail):
            let compactDetail = detail.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return "El router rechazo AddPortMapping (HTTP \(code)). \(compactDetail)"
        case .invalidDescription(let detail):
            return "La descripcion UPnP del router no era usable: \(detail)"
        }
    }
}

private final class SynchronizedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

final class UPnPDeviceDescriptionParser {
    func parse(data: Data, descriptionURL: URL) throws -> UPnPInternetGatewayService? {
        guard let xml = String(data: data, encoding: .utf8) else {
            throw UPnPPortMapperError.invalidDescription("La descripcion XML no estaba en UTF-8.")
        }

        let urlBase = firstTagValue(named: "URLBase", in: xml)
        let serviceBlocks = blocks(named: "service", in: xml)
        let supportedService = serviceBlocks.first { block in
            guard let serviceType = firstTagValue(named: "serviceType", in: block) else {
                return false
            }
            return serviceType.contains("WANIPConnection") || serviceType.contains("WANPPPConnection")
        }

        guard let supportedService,
              let serviceType = firstTagValue(named: "serviceType", in: supportedService),
              let controlURLText = firstTagValue(named: "controlURL", in: supportedService),
              let controlURL = resolveControlURL(
                controlURLText,
                urlBase: urlBase,
                descriptionURL: descriptionURL
              ) else {
            return nil
        }

        return UPnPInternetGatewayService(serviceType: serviceType, controlURL: controlURL)
    }

    private func resolveControlURL(_ controlURLText: String, urlBase: String?, descriptionURL: URL) -> URL? {
        if let absolute = URL(string: controlURLText), absolute.scheme != nil {
            return absolute
        }

        if let urlBase,
           let baseURL = URL(string: urlBase),
           let resolved = URL(string: controlURLText, relativeTo: baseURL)?.absoluteURL {
            return resolved
        }

        return URL(string: controlURLText, relativeTo: descriptionURL)?.absoluteURL
    }

    private func firstTagValue(named tagName: String, in text: String) -> String? {
        guard let startRange = text.range(of: "<\(tagName)>"),
              let endRange = text.range(of: "</\(tagName)>") else {
            return nil
        }

        let valueRange = startRange.upperBound..<endRange.lowerBound
        return text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func blocks(named tagName: String, in text: String) -> [String] {
        let startToken = "<\(tagName)>"
        let endToken = "</\(tagName)>"
        var searchRange = text.startIndex..<text.endIndex
        var results: [String] = []

        while let startRange = text.range(of: startToken, range: searchRange),
              let endRange = text.range(of: endToken, range: startRange.upperBound..<text.endIndex) {
            let valueRange = startRange.upperBound..<endRange.lowerBound
            results.append(String(text[valueRange]))
            searchRange = endRange.upperBound..<text.endIndex
        }

        return results
    }
}
