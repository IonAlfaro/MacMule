import Foundation

public struct JSONRPCRequest: Codable, Equatable, Sendable {
    public var jsonrpc: String
    public var id: Int?
    public var method: String
    public var params: [String: String]?

    public init(
        jsonrpc: String = "2.0",
        id: Int? = nil,
        method: String,
        params: [String: String]? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCErrorBody: Codable, Equatable, Sendable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct JSONRPCResponse: Codable, Equatable, Sendable {
    public var jsonrpc: String
    public var id: Int?
    public var result: CoreRPCResult?
    public var error: JSONRPCErrorBody?

    public init(
        jsonrpc: String = "2.0",
        id: Int?,
        result: CoreRPCResult? = nil,
        error: JSONRPCErrorBody? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum CoreRPCResult: Equatable, Sendable {
    case snapshot(CoreSnapshot)
    case eventBatch(CoreEventBatch)

    public var snapshot: CoreSnapshot? {
        guard case .snapshot(let snapshot) = self else { return nil }
        return snapshot
    }

    public var eventBatch: CoreEventBatch? {
        guard case .eventBatch(let eventBatch) = self else { return nil }
        return eventBatch
    }
}

extension CoreRPCResult: Codable {
    public init(from decoder: Decoder) throws {
        if let eventBatch = try? CoreEventBatch(from: decoder) {
            self = .eventBatch(eventBatch)
            return
        }

        self = .snapshot(try CoreSnapshot(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .snapshot(let snapshot):
            try snapshot.encode(to: encoder)
        case .eventBatch(let eventBatch):
            try eventBatch.encode(to: encoder)
        }
    }
}

public final class CoreRPCHandler {
    private let service: MacMuleCoreService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(service: MacMuleCoreService = MacMuleCoreService()) {
        self.service = service
        encoder.outputFormatting = [.sortedKeys]
    }

    public func handle(_ input: Data) -> Data {
        let response: JSONRPCResponse

        do {
            let request = try decoder.decode(JSONRPCRequest.self, from: input)
            response = handle(request)
        } catch {
            response = JSONRPCResponse(
                id: nil,
                error: JSONRPCErrorBody(code: -32700, message: "Parse error")
            )
        }

        return encode(response)
    }

    public func handle(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard request.jsonrpc == "2.0" else {
            return error(id: request.id, code: -32600, message: "Invalid JSON-RPC version")
        }

        do {
            switch request.method {
            case "snapshot":
                return success(id: request.id, result: service.snapshot())
            case "events_since":
                let after = try sequenceParam("after", in: request)
                return success(id: request.id, result: service.events(after: after))
            case "add_ed2k_link":
                let link = try requiredParam("link", in: request)
                let initialSources = try initialSources(in: request)
                return success(id: request.id, result: try service.addED2KLink(ED2KLinkParser.parseFileLink(link), initialSources: initialSources))
            case "search":
                let query = try requiredParam("query", in: request)
                return success(id: request.id, result: service.search(query: query))
            case "pause":
                let id = try requiredParam("id", in: request)
                return success(id: request.id, result: try service.pauseTransfer(id: id))
            case "resume":
                let id = try requiredParam("id", in: request)
                return success(id: request.id, result: try service.resumeTransfer(id: id))
            case "remove":
                let id = try requiredParam("id", in: request)
                return success(id: request.id, result: try service.removeTransfer(id: id))
            case "write_block":
                let id = try requiredParam("id", in: request)
                let offset = try requiredUInt64Param("offset", in: request)
                let data = try requiredBase64DataParam("data_base64", in: request)
                return success(id: request.id, result: try service.writeBlock(id: id, offset: offset, data: data))
            case "connect_server":
                return success(id: request.id, result: service.connectToServer(try connectConfiguration(in: request)))
            case "disconnect_server":
                return success(id: request.id, result: service.disconnectServer())
            case "add_server":
                return success(
                    id: request.id,
                    result: try service.addServer(
                        endpoint: try serverEndpoint(in: request),
                        name: optionalParam("name", in: request)
                    )
                )
            case "remove_server":
                return success(id: request.id, result: try service.removeServer(endpoint: try serverEndpoint(in: request)))
            case "import_servers":
                return success(id: request.id, result: try service.importServers(parseServerEndpoints(in: request)))
            case "set_config":
                let maxDown = try optionalIntParam("max_download_kbps", in: request) ?? 0
                let maxUp = try optionalIntParam("max_upload_kbps", in: request) ?? 0
                return success(id: request.id, result: service.setConfig(maxDownloadKbps: maxDown, maxUploadKbps: maxUp))
            case "kad_start":
                return success(id: request.id, result: service.kadStart())
            case "kad_stop":
                return success(id: request.id, result: service.kadStop())
            case "kad_bootstrap":
                let ip = try requiredParam("ip", in: request)
                let port = try requiredUInt16Param("port", in: request)
                return success(id: request.id, result: service.kadBootstrap(ip: ip, port: port))
            case "kad_search_keyword":
                let query = try requiredParam("query", in: request)
                return success(id: request.id, result: service.kadSearchKeyword(query: query))
            case "kad_search_sources":
                let hash = try requiredParam("hash", in: request)
                return success(id: request.id, result: service.kadSearchSources(hash: hash))
            case "web_start":
                let port = try requiredUInt16Param("port", in: request)
                let password = try optionalParam("password", in: request) ?? ""
                return success(id: request.id, result: service.webStart(port: port, password: password))
            case "web_stop":
                return success(id: request.id, result: service.webStop())
            case "scheduler_enable":
                let enabled = try requiredParam("enabled", in: request) == "true"
                return success(id: request.id, result: service.schedulerEnable(enabled))
            case "scheduler_add_entry":
                let entryParam = try requiredParam("entry", in: request)
                let data = Data(entryParam.utf8)
                let entry = try JSONDecoder().decode(ScheduleEntry.self, from: data)
                return success(id: request.id, result: service.schedulerAddEntry(entry))
            case "scheduler_remove_entry":
                let id = try requiredParam("id", in: request)
                guard let uuid = UUID(uuidString: id) else {
                    throw RPCParamError.invalid("id")
                }
                return success(id: request.id, result: service.schedulerRemoveEntry(id: uuid))
            default:
                return error(id: request.id, code: -32601, message: "Method not found")
            }
        } catch let error as RPCParamError {
            return self.error(id: request.id, code: -32602, message: error.localizedDescription)
        } catch let error as ED2KLinkParseError {
            return self.error(id: request.id, code: -32602, message: error.localizedDescription)
        } catch let error as CoreServiceError {
            return self.error(id: request.id, code: -32000, message: error.localizedDescription)
        } catch let error as CoreTransferStoreError {
            return self.error(id: request.id, code: -32000, message: error.localizedDescription)
        } catch {
            return self.error(id: request.id, code: -32603, message: "Internal error")
        }
    }

    private func sequenceParam(_ name: String, in request: JSONRPCRequest) throws -> UInt64 {
        guard let rawValue = request.params?[name], rawValue.isEmpty == false else {
            return 0
        }

        guard let value = UInt64(rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return value
    }

    private func requiredUInt64Param(_ name: String, in request: JSONRPCRequest) throws -> UInt64 {
        let rawValue = try requiredParam(name, in: request)

        guard let value = UInt64(rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return value
    }

    private func requiredBase64DataParam(_ name: String, in request: JSONRPCRequest) throws -> Data {
        let rawValue = try requiredParam(name, in: request)

        guard let data = Data(base64Encoded: rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return data
    }

    private func initialSources(in request: JSONRPCRequest) throws -> [ED2KFoundSource] {
        guard let sourceClientID = try optionalUInt32Param("source_client_id", in: request),
              let sourceClientPort = try optionalUInt16Param("source_client_port", in: request) else {
            return []
        }

        return [ED2KFoundSource(clientID: sourceClientID, clientPort: sourceClientPort)]
    }

    private func requiredParam(_ name: String, in request: JSONRPCRequest) throws -> String {
        guard let value = request.params?[name], value.isEmpty == false else {
            throw RPCParamError.missing(name)
        }
        return value
    }

    private func connectConfiguration(in request: JSONRPCRequest) throws -> ED2KServerSessionConfiguration {
        let endpoint = try serverEndpoint(in: request)
        let tcpPort = try optionalUInt16Param("tcp_port", in: request) ?? 4662
        let clientID = try optionalUInt32Param("client_id", in: request) ?? 0
        let protocolVersion = try optionalUInt32Param("protocol_version", in: request) ?? ED2KLoginRequest.defaultProtocolVersion
        let flags = try optionalUInt32Param("flags", in: request) ?? ED2KLoginRequest.defaultCompressionFlags
        let nickname = request.params?["nickname"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userHash = try optionalBase64DataParam("user_hash_base64", in: request) ?? defaultUserHash()

        guard userHash.count == 16 else {
            throw RPCParamError.invalid("user_hash_base64")
        }

        return ED2KServerSessionConfiguration(
            endpoint: endpoint,
            userHash: userHash,
            clientID: clientID,
            tcpPort: tcpPort,
            nickname: nickname?.isEmpty == false ? nickname! : "MacMule",
            protocolVersion: protocolVersion,
            flags: flags
        )
    }

    private func serverEndpoint(in request: JSONRPCRequest) throws -> ED2KServerEndpoint {
        let host = optionalParam("host", in: request)
        let port = try optionalUInt16Param("port", in: request)

        if let host, let port {
            return ED2KServerEndpoint(host: host, port: port)
        }

        if host != nil || port != nil {
            throw RPCParamError.invalid("host")
        }

        if let preferredEndpoint = service.preferredServerEndpoint() {
            return preferredEndpoint
        }

        throw RPCParamError.missing("host")
    }

    private func requiredUInt16Param(_ name: String, in request: JSONRPCRequest) throws -> UInt16 {
        let rawValue = try requiredParam(name, in: request)

        guard let value = UInt16(rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return value
    }

    private func optionalUInt16Param(_ name: String, in request: JSONRPCRequest) throws -> UInt16? {
        guard let rawValue = request.params?[name], rawValue.isEmpty == false else {
            return nil
        }

        guard let value = UInt16(rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return value
    }

    private func optionalUInt32Param(_ name: String, in request: JSONRPCRequest) throws -> UInt32? {
        guard let rawValue = request.params?[name], rawValue.isEmpty == false else {
            return nil
        }

        guard let value = UInt32(rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return value
    }

    private func optionalBase64DataParam(_ name: String, in request: JSONRPCRequest) throws -> Data? {
        guard let rawValue = request.params?[name], rawValue.isEmpty == false else {
            return nil
        }

        guard let data = Data(base64Encoded: rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return data
    }

    private func optionalParam(_ name: String, in request: JSONRPCRequest) -> String? {
        guard let value = request.params?[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        return value
    }

    private func optionalIntParam(_ name: String, in request: JSONRPCRequest) throws -> Int? {
        guard let rawValue = request.params?[name], rawValue.isEmpty == false else {
            return nil
        }

        guard let value = Int(rawValue) else {
            throw RPCParamError.invalid(name)
        }

        return value
    }

    private func parseServerEndpoints(in request: JSONRPCRequest) throws -> [ED2KServerEndpoint] {
        let rawValue = try requiredParam("addresses", in: request)
        let separators = CharacterSet(charactersIn: ",;\n\r\t")
        let addresses = rawValue
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard addresses.isEmpty == false else {
            throw RPCParamError.invalid("addresses")
        }

        return try addresses.map(parseServerEndpoint)
    }

    private func parseServerEndpoint(_ address: String) throws -> ED2KServerEndpoint {
        guard let separator = address.lastIndex(of: ":") else {
            throw RPCParamError.invalid("addresses")
        }

        let host = String(address[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPort = String(address[address.index(after: separator)...])

        guard host.isEmpty == false, let port = UInt16(rawPort) else {
            throw RPCParamError.invalid("addresses")
        }

        return ED2KServerEndpoint(host: host, port: port)
    }

    private func defaultUserHash() -> Data {
        service.userHash()
    }

    private func success(id: Int?, result: CoreSnapshot) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: .snapshot(result))
    }

    private func success(id: Int?, result: CoreEventBatch) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: .eventBatch(result))
    }

    private func error(id: Int?, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, error: JSONRPCErrorBody(code: code, message: message))
    }

    private func encode(_ response: JSONRPCResponse) -> Data {
        do {
            return try encoder.encode(response)
        } catch {
            return Data(#"{"error":{"code":-32603,"message":"Encoding error"},"id":null,"jsonrpc":"2.0"}"#.utf8)
        }
    }
}

private enum RPCParamError: Error, LocalizedError {
    case missing(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "Missing required parameter: \(name)."
        case .invalid(let name):
            return "Invalid parameter: \(name)."
        }
    }
}
