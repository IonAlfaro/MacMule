import Foundation
import Network

public final class CoreWebServer: @unchecked Sendable {
    public private(set) var isRunning = false
    public private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.macmule.web", qos: .utility)
    private let serviceProvider: () -> CoreSnapshot
    private let commandHandler: (String, [String: String]) -> CoreSnapshot?
    private let logHandler: (@Sendable (String) -> Void)?
    private var password: String = ""
    private var isAuthenticated = false

    public init(
        serviceProvider: @escaping () -> CoreSnapshot,
        commandHandler: @escaping (String, [String: String]) -> CoreSnapshot?,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.serviceProvider = serviceProvider
        self.commandHandler = commandHandler
        self.logHandler = logHandler
    }

    public func start(port: UInt16, password: String = "") throws {
        guard !isRunning else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw WebServerError.invalidPort(port)
        }

        self.password = password
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: nwPort)

        listener?.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                self?.isRunning = true
                self?.port = port
                self?.log("Web server started on port \(port)")
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: queue)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        listener?.cancel()
        listener = nil
        port = 0
        log("Web server stopped")
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            self.processHTTPRequest(data, connection: connection)
        }
    }

    private func processHTTPRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection, status: 400, body: "Bad Request")
            return
        }

        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, requestLine.hasPrefix("GET") || requestLine.hasPrefix("POST") else {
            sendResponse(connection, status: 400, body: "Bad Request")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection, status: 400, body: "")
            return
        }

        let method = parts[0]
        let fullPath = parts[1]
        let pathComponents = fullPath.components(separatedBy: "?")
        let path = pathComponents[0]

        // Parse query params
        var queryParams: [String: String] = [:]
        if pathComponents.count > 1 {
            for param in pathComponents[1].components(separatedBy: "&") {
                let kv = param.components(separatedBy: "=")
                if kv.count == 2 {
                    queryParams[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        // Parse POST body
        if method == "POST" {
            let bodyStart = request.range(of: "\r\n\r\n").map { request[$0.upperBound...] } ?? ""
            if !bodyStart.isEmpty {
                for param in bodyStart.components(separatedBy: "&") {
                    let kv = param.components(separatedBy: "=")
                    if kv.count == 2 {
                        queryParams[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                    }
                }
            }
        }

        switch path {
        case "/":
            let snapshot = serviceProvider()
            let html = generateHTML(snapshot: snapshot)
            sendResponse(connection, status: 200, body: html, contentType: "text/html")

        case "/status":
            let snapshot = serviceProvider()
            let json = encodeJSON(snapshot: snapshot)
            sendResponse(connection, status: 200, body: json, contentType: "application/json")

        case "/connect":
            _ = commandHandler("connect_server", queryParams)
            sendRedirect(connection, to: "/")

        case "/disconnect":
            _ = commandHandler("disconnect_server", [:])
            sendRedirect(connection, to: "/")

        case "/search":
            if let query = queryParams["q"] {
                _ = commandHandler("search", ["query": query])
            }
            sendRedirect(connection, to: "/")

        case "/add_link":
            if let link = queryParams["link"] {
                _ = commandHandler("add_ed2k_link", ["link": link])
            }
            sendRedirect(connection, to: "/")

        default:
            sendResponse(connection, status: 404, body: "Not Found")
        }
    }

    private func sendResponse(_ connection: NWConnection, status: Int, body: String, contentType: String = "text/plain") {
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        let response = """
        HTTP/1.1 \(status) \(statusText)\r\n
        Content-Type: \(contentType); charset=utf-8\r\n
        Content-Length: \(body.utf8.count)\r\n
        Connection: close\r\n
        \r\n
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendRedirect(_ connection: NWConnection, to path: String) {
        let response = """
        HTTP/1.1 302 Found\r\n
        Location: \(path)\r\n
        Content-Length: 0\r\n
        Connection: close\r\n
        \r\n
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func encodeJSON(snapshot: CoreSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func generateHTML(snapshot: CoreSnapshot) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        let downTotal = snapshot.transfers.reduce(0 as UInt64) { $0 + $1.completedBytes }
        let activeTransfers = snapshot.transfers.filter { $0.status == .downloading }.count

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>MacMule Web Interface</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, sans-serif; background: #1a1a2e; color: #eee; padding: 20px; }
        h1 { font-size: 1.5rem; margin-bottom: 20px; color: #00d4aa; }
        .card { background: #16213e; border-radius: 10px; padding: 16px; margin-bottom: 16px; }
        .card h2 { font-size: 1rem; color: #0f3460; margin-bottom: 10px; }
        .stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; }
        .stat { background: #0f3460; padding: 10px; border-radius: 8px; }
        .stat .label { font-size: 0.75rem; color: #888; }
        .stat .value { font-size: 1rem; font-weight: bold; margin-top: 2px; }
        table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
        th, td { padding: 6px 10px; text-align: left; border-bottom: 1px solid #0f3460; }
        th { color: #888; font-weight: normal; }
        .actions { margin-top: 16px; display: flex; gap: 8px; flex-wrap: wrap; }
        .actions a { background: #00d4aa; color: #1a1a2e; padding: 8px 16px; border-radius: 6px; text-decoration: none; font-size: 0.85rem; font-weight: 500; }
        .actions a.danger { background: #e94560; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 0.75rem; }
        .badge.downloading { background: #00d4aa; color: #1a1a2e; }
        .badge.paused { background: #e94560; color: white; }
        .badge.completed { background: #0f3460; color: #888; }
        .search-box { display: flex; gap: 8px; margin-bottom: 12px; }
        .search-box input { flex: 1; padding: 8px 12px; border: none; border-radius: 6px; background: #0f3460; color: #eee; font-size: 0.85rem; }
        .search-box button { padding: 8px 16px; border: none; border-radius: 6px; background: #00d4aa; color: #1a1a2e; cursor: pointer; }
        </style>
        </head>
        <body>
        <h1>MacMule</h1>

        <div class="stat-grid">
        <div class="stat"><div class="label">Status</div><div class="value">\(snapshot.network.isConnected ? "Connected" : "Disconnected")</div></div>
        <div class="stat"><div class="label">Active downloads</div><div class="value">\(activeTransfers)</div></div>
        <div class="stat"><div class="label">Downloaded</div><div class="value">\(formatter.string(fromByteCount: Int64(downTotal)))</div></div>
        <div class="stat"><div class="label">Kad Nodes</div><div class="value">\(snapshot.kad.nodeCount)</div></div>
        </div>

        <div class="card">
        <h2>Quick actions</h2>
        <div class="actions">
        <a href="/connect">Connect</a>
        <a href="/disconnect" class="danger">Disconnect</a>
        </div>
        <div class="search-box" style="margin-top:12px">
        <form action="/search" method="get" style="display:flex;gap:8px;width:100%">
        <input type="text" name="q" placeholder="Search the eD2k network...">
        <button type="submit">Search</button>
        </form>
        </div>
        <div class="search-box">
        <form action="/add_link" method="get" style="display:flex;gap:8px;width:100%">
        <input type="text" name="link" placeholder="ed2k://|file|...">
        <button type="submit">Add</button>
        </form>
        </div>
        </div>

        <div class="card">
        <h2>Downloads (\(snapshot.transfers.count))</h2>
        <table>
        <tr><th>Name</th><th>Size</th><th>Progress</th><th>Speed</th><th>Status</th></tr>
        \(snapshot.transfers.map { t in
        """
        <tr>
        <td>\(escapeHTML(t.fileName))</td>
        <td>\(formatter.string(fromByteCount: Int64(t.sizeInBytes)))</td>
        <td>\(t.sizeInBytes > 0 ? "\(Int(Double(t.completedBytes) / Double(t.sizeInBytes) * 100))%" : "0%")</td>
        <td>\(formatter.string(fromByteCount: Int64(t.downloadSpeedBytesPerSecond)))/s</td>
        <td><span class="badge \(t.status.rawValue)">\(t.status.rawValue)</span></td>
        </tr>
        """
        }.joined())
        </table>
        </div>

        <div class="card">
        <h2>Servers (\(snapshot.servers.count))</h2>
        <table>
        <tr><th>Name</th><th>Address</th><th>Users</th><th>Ping</th></tr>
        \(snapshot.servers.map { s in
        "<tr><td>\(escapeHTML(s.name))</td><td>\(s.endpoint.address)</td><td>\(s.users)</td><td>\(s.pingMilliseconds)ms</td></tr>"
        }.joined())
        </table>
        </div>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}

public enum WebServerError: Error, Equatable, LocalizedError {
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid web server port: \(port)."
        }
    }
}
