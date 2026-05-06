import Darwin
import Foundation
import MacMuleCore

@MainActor
final class DaemonMacMuleCoreClient: MacMuleCoreClient {
    private var socketPath: String
    private var daemonSession: MacMuleDaemonSession?
    private var incomingDirectory: URL?
    private var tempDirectory: URL?
    private var storageDirectory: URL?
    private let baseRuntimeStatus: MacMuleCoreRuntimeStatus
    private var lastTransportError: String?
    private var clientLogs: [MacMuleCoreLogEntry] = []
    private var nextRequestID = 1

    var runtimeStatus: MacMuleCoreRuntimeStatus {
        if let daemonSession, daemonSession.isRunning == false {
            return MacMuleCoreRuntimeStatus(
                title: baseRuntimeStatus.title,
                detail: "Daemon stopped",
                systemImage: "exclamationmark.triangle",
                isWarning: true
            )
        }
        return baseRuntimeStatus
    }

    var runtimeLogs: [MacMuleCoreLogEntry] {
        (daemonSession?.logs ?? []) + clientLogs
    }

    var canRestartCore: Bool {
        daemonSession?.ownsProcess ?? false
    }

    init(
        socketPath: String,
        daemonSession: MacMuleDaemonSession? = nil,
        storageDirectory: URL? = nil,
        incomingDirectory: URL? = nil,
        tempDirectory: URL? = nil,
        baseRuntimeStatus: MacMuleCoreRuntimeStatus
    ) {
        self.socketPath = socketPath
        self.daemonSession = daemonSession
        self.storageDirectory = daemonSession?.storageDirectory ?? storageDirectory
        self.incomingDirectory = daemonSession?.incomingDirectory ?? incomingDirectory
        self.tempDirectory = daemonSession?.tempDirectory ?? tempDirectory
        self.baseRuntimeStatus = baseRuntimeStatus
        recordClientLog(.info, "Core client connected through Unix socket.")
    }

    func currentSnapshot() async -> MacMuleSnapshot {
        await perform(method: "snapshot")
    }

    func events(after sequence: UInt64) async -> MacMuleEventBatch {
        let requestID = nextRequestID
        nextRequestID += 1

        let request = JSONRPCRequest(
            id: requestID,
            method: "events_since",
            params: ["after": String(sequence)]
        )
        let path = socketPath

        do {
            let response: JSONRPCResponse = try await Task.detached(priority: .userInitiated) {
                try UnixSocketRPCClient(socketPath: path).send(request)
            }.value
            if let eventBatch = response.result?.eventBatch {
                lastTransportError = nil
                return MacMuleEventBatch(coreEventBatch: eventBatch)
            }
        } catch {
            recordTransportError(error)
        }

        return .empty(after: sequence)
    }

    func search(query: String) async -> MacMuleSnapshot {
        await perform(
            method: "search",
            params: ["query": query]
        )
    }

    func addDownload(from result: SearchResult) async -> MacMuleSnapshot {
        let link = ED2KFileLink(
            fileName: result.fileName,
            sizeInBytes: UInt64(max(result.sizeInBytes, 0)),
            hash: result.ed2kHash
        )
        var params = ["link": link.canonicalURL]
        if let sourceClientID = result.sourceClientID {
            params["source_client_id"] = String(sourceClientID)
            params["source_client_port"] = String(result.sourceClientPort ?? 4662)
        }
        return await perform(method: "add_ed2k_link", params: params)
    }

    func addED2KLink(_ link: ED2KFileLink) async -> MacMuleSnapshot {
        await perform(
            method: "add_ed2k_link",
            params: ["link": link.canonicalURL]
        )
    }

    func setDownloadPaused(id: TransferItem.ID, paused: Bool) async -> MacMuleSnapshot {
        await perform(
            method: paused ? "pause" : "resume",
            params: ["id": id.uuidString]
        )
    }

    func removeDownload(id: TransferItem.ID) async -> MacMuleSnapshot {
        await perform(
            method: "remove",
            params: ["id": id.uuidString]
        )
    }

    func setConnection(enabled: Bool) async -> MacMuleSnapshot {
        if enabled == false {
            return await perform(method: "disconnect_server")
        }

        if let endpoint = preferredServerEndpoint() {
            return await perform(
                method: "connect_server",
                params: [
                    "host": endpoint.host,
                    "port": String(endpoint.port)
                ]
            )
        }

        return await perform(method: "connect_server")
    }

    func connectToServer(host: String, port: UInt16) async -> MacMuleSnapshot {
        await perform(
            method: "connect_server",
            params: [
                "host": host,
                "port": String(port)
            ]
        )
    }

    func addServer(host: String, port: UInt16) async -> MacMuleSnapshot {
        await perform(
            method: "add_server",
            params: [
                "host": host,
                "port": String(port)
            ]
        )
    }

    func removeServer(host: String, port: UInt16) async -> MacMuleSnapshot {
        await perform(
            method: "remove_server",
            params: [
                "host": host,
                "port": String(port)
            ]
        )
    }

    func importServers(servers: [(host: String, port: UInt16)]) async -> MacMuleSnapshot {
        guard servers.isEmpty == false else { return await currentSnapshot() }
        let addresses = servers.map { "\($0.host):\($0.port)" }.joined(separator: ",")
        return await perform(
            method: "import_servers",
            params: ["addresses": addresses]
        )
    }

    func restartCore() async -> MacMuleSnapshot {
        guard daemonSession != nil else {
            recordClientLog(.warning, "External socket cannot be restarted from MacMule.")
            return await currentSnapshot()
        }

        daemonSession?.stop()
        daemonSession = nil
        lastTransportError = nil
        recordClientLog(.warning, "Restarting local daemon.")

        guard let session = await MacMuleDaemonLauncher.launchBundledDaemonAsync(
            forceFresh: true,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory
        ) else {
            lastTransportError = "Could not restart the local daemon."
            recordClientLog(.error, "Could not restart the local daemon.")
            return .empty
        }

        await Task.yield()

        socketPath = session.socketPath
        daemonSession = session
        storageDirectory = session.storageDirectory
        incomingDirectory = session.incomingDirectory
        tempDirectory = session.tempDirectory
        recordClientLog(.info, "Local daemon restarted.")
        return await currentSnapshot()
    }

    func kadStart() async -> MacMuleSnapshot {
        await perform(method: "kad_start")
    }

    func kadStop() async -> MacMuleSnapshot {
        await perform(method: "kad_stop")
    }

    func kadBootstrap(host: String, port: UInt16) async -> MacMuleSnapshot {
        await perform(method: "kad_bootstrap", params: ["ip": host, "port": String(port)])
    }

    func kadSearchKeyword(query: String) async -> MacMuleSnapshot {
        await perform(method: "kad_search_keyword", params: ["query": query])
    }

    func kadSearchSources(hash: String) async -> MacMuleSnapshot {
        await perform(method: "kad_search_sources", params: ["hash": hash])
    }

    func addCategory(title: String, color: String) async -> MacMuleSnapshot {
        await perform(method: "add_category", params: ["title": title, "color": color])
    }

    func removeCategory(id: UUID) async -> MacMuleSnapshot {
        await perform(method: "remove_category", params: ["id": id.uuidString])
    }

    func schedulerEnable(enabled: Bool) async -> MacMuleSnapshot {
        await perform(method: "scheduler_enable", params: ["enabled": enabled ? "true" : "false"])
    }

    func schedulerAddEntry(title: String, days: Set<Int>, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, actions: [String]) async -> MacMuleSnapshot {
        let entry = ScheduleEntry(
            title: title,
            days: days,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            actions: actions.map { ScheduleAction(type: ScheduleActionType(rawValue: $0) ?? .setUploadLimit) }
        )
        guard let encoded = try? JSONEncoder().encode(entry),
              let entryData = String(data: encoded, encoding: .utf8) else {
            return await currentSnapshot()
        }
        return await perform(method: "scheduler_add_entry", params: ["entry": entryData])
    }

    func schedulerRemoveEntry(id: UUID) async -> MacMuleSnapshot {
        await perform(method: "scheduler_remove_entry", params: ["id": id.uuidString])
    }

    func setConfig(maxDownloadKilobytes: Int, maxUploadKilobytes: Int) async -> MacMuleSnapshot {
        await perform(
            method: "set_config",
            params: [
                "max_download_kbps": String(maxDownloadKilobytes),
                "max_upload_kbps": String(maxUploadKilobytes)
            ]
        )
    }

    private func perform(method: String, params: [String: String]? = nil) async -> MacMuleSnapshot {
        let requestID = nextRequestID
        nextRequestID += 1

        let request = JSONRPCRequest(id: requestID, method: method, params: params)
        let path = socketPath

        do {
            let response: JSONRPCResponse = try await Task.detached(priority: .userInitiated) {
                try UnixSocketRPCClient(socketPath: path).send(request)
            }.value
            if let result = response.result?.snapshot {
                lastTransportError = nil
                return MacMuleSnapshot(coreSnapshot: result)
            }
        } catch {
            recordTransportError(error)
        }

        return .empty
    }

    private func recordTransportError(_ error: Error) {
        let message = error.localizedDescription
        if lastTransportError != message {
            recordClientLog(.error, message)
        }
        lastTransportError = message
    }

    private func recordClientLog(_ level: MacMuleCoreLogLevel, _ message: String) {
        clientLogs.append(
            MacMuleCoreLogEntry(
                timestamp: Date(),
                level: level,
                message: message
            )
        )

        if clientLogs.count > 200 {
            clientLogs.removeFirst(clientLogs.count - 200)
        }
    }

    private func preferredServerEndpoint() -> ED2KServerEndpoint? {
        let environment = ProcessInfo.processInfo.environment
        if let host = environment["MACMULE_ED2K_SERVER_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           host.isEmpty == false,
           let rawPort = environment["MACMULE_ED2K_SERVER_PORT"],
           let port = UInt16(rawPort) {
            return ED2KServerEndpoint(host: host, port: port)
        }

        return nil
    }

}

private struct UnixSocketRPCClient {
    let socketPath: String
    var timeoutSeconds: Int32 = 8

    func send(_ request: JSONRPCRequest) throws -> JSONRPCResponse {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw UnixSocketRPCError.socketCreationFailed(errno)
        }
        defer {
            close(fileDescriptor)
        }

        // Apply send + receive timeouts so we never block the thread indefinitely
        var timeout = timeval(tv_sec: __darwin_time_t(timeoutSeconds), tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try connect(fileDescriptor)

        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0A)
        try writeAll(requestData, to: fileDescriptor)

        let responseData = try readLine(from: fileDescriptor)
        return try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
    }

    private func connect(_ fileDescriptor: Int32) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString.map { UInt8(bitPattern: $0) }
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw UnixSocketRPCError.pathTooLong(socketPath)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            throw UnixSocketRPCError.connectFailed(errno)
        }
    }

    private func writeAll(_ data: Data, to fileDescriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var bytesWritten = 0
            while bytesWritten < data.count {
                let result = write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    data.count - bytesWritten
                )

                guard result > 0 else {
                    throw UnixSocketRPCError.writeFailed(errno)
                }

                bytesWritten += result
            }
        }
    }

    private func readLine(from fileDescriptor: Int32) throws -> Data {
        var response = Data()
        var byte: UInt8 = 0

        while true {
            let bytesRead = read(fileDescriptor, &byte, 1)

            guard bytesRead > 0 else {
                throw UnixSocketRPCError.readFailed(errno)
            }

            if byte == 0x0A {
                return response
            }

            response.append(byte)
        }
    }
}

private enum UnixSocketRPCError: Error {
    case pathTooLong(String)
    case socketCreationFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
}

extension UnixSocketRPCError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .pathTooLong:
            return "Socket path is too long."
        case .socketCreationFailed(let code):
            return "Could not create Unix socket (errno \(code))."
        case .connectFailed(let code):
            return "Could not connect to daemon (errno \(code))."
        case .writeFailed(let code):
            return "Could not send request to daemon (errno \(code))."
        case .readFailed(let code):
            return "Could not read response from daemon (errno \(code))."
        }
    }
}

private extension MacMuleSnapshot {
    nonisolated init(coreSnapshot: CoreSnapshot) {
        let downloads = coreSnapshot.transfers.map { TransferItem(coreTransfer: $0) }
        let kadState = MacMuleSnapshot.KadState(
            isRunning: coreSnapshot.kad.isRunning,
            isConnected: coreSnapshot.kad.isConnected,
            isFirewalled: coreSnapshot.kad.isFirewalled,
            nodeCount: coreSnapshot.kad.nodeCount,
            activeSearchCount: coreSnapshot.kad.activeSearchCount,
            totalKeywords: coreSnapshot.kad.totalKeywords,
            totalSources: coreSnapshot.kad.totalSources,
            nodes: [],
            bucketStats: [],
            activeSearches: []
        )
        self.init(
            downloads: downloads,
            uploads: [],
            searchResults: coreSnapshot.searchResults.map(SearchResult.init(coreSearchResult:)),
            servers: coreSnapshot.servers.map(ServerSnapshot.init(coreServer:)),
            sharedFiles: [],
            statistics: Self.statistics(for: downloads),
            network: NetworkSummary(coreNetwork: coreSnapshot.network),
            kad: kadState,
            transferPeers: coreSnapshot.transferPeers.mapValues { peers in
                peers.map { SourceDetail(corePeer: $0) }
            },
            categories: coreSnapshot.categories.map { CategoryItem(id: $0.id, title: $0.title, color: $0.color) }
        )
    }

    nonisolated static func statistics(for downloads: [TransferItem]) -> [StatMetric] {
        let downloaded = downloads.reduce(Int64(0)) { $0 + $1.completedBytes }
        let uploaded = downloads.reduce(Int64(0)) { $0 + $1.uploadSpeedBytesPerSecond }
        let ratio = downloaded > 0 ? Double(uploaded) / Double(downloaded) : 0

        return [
            StatMetric(title: "Downloaded", value: ByteCountFormatter.macMuleString(downloaded), systemImage: "arrow.down.circle"),
            StatMetric(title: "Uploaded", value: ByteCountFormatter.macMuleString(uploaded), systemImage: "arrow.up.circle"),
            StatMetric(title: "Ratio", value: String(format: "%.2f", ratio), systemImage: "percent"),
            StatMetric(title: "Session", value: "0 m", systemImage: "timer")
        ]
    }
}

private extension MacMuleEventBatch {
    nonisolated init(coreEventBatch: CoreEventBatch) {
        self.init(
            afterSequence: coreEventBatch.afterSequence,
            latestSequence: coreEventBatch.latestSequence,
            events: coreEventBatch.events.compactMap(MacMuleCoreEvent.init(coreEvent:)),
            snapshot: MacMuleSnapshot(coreSnapshot: coreEventBatch.snapshot)
        )
    }
}

private extension MacMuleCoreEvent {
    nonisolated init?(coreEvent: CoreEvent) {
        switch coreEvent.kind {
        case .transferAdded:
            guard let id = coreEvent.transferID else { return nil }
            self = .downloadAdded(id)
        case .transferUpdated:
            guard let id = coreEvent.transferID else { return nil }
            self = .downloadUpdated(id)
        case .transferRemoved:
            guard let id = coreEvent.transferID else { return nil }
            self = .downloadRemoved(id)
        case .networkUpdated:
            self = .snapshotChanged
        case .kadUpdated:
            self = .snapshotChanged
        case .kadSearchResult:
            self = .snapshotChanged
        }
    }
}

private extension TransferItem {
    nonisolated init(coreTransfer: CoreTransfer) {
        let size = min(coreTransfer.sizeInBytes, UInt64(Int64.max))
        let completed = min(coreTransfer.completedBytes, UInt64(Int64.max))
        let downloadSpeed = min(coreTransfer.downloadSpeedBytesPerSecond, UInt64(Int64.max))
        let uploadSpeed = min(coreTransfer.uploadSpeedBytesPerSecond, UInt64(Int64.max))

        self.init(
            id: coreTransfer.id,
            fileName: coreTransfer.fileName,
            kind: FileKind(coreKind: coreTransfer.kind),
            sizeInBytes: Int64(size),
            completedBytes: Int64(completed),
            downloadSpeedBytesPerSecond: Int64(downloadSpeed),
            uploadSpeedBytesPerSecond: Int64(uploadSpeed),
            sources: coreTransfer.sources,
            availability: coreTransfer.availability,
            status: TransferStatus(coreStatus: coreTransfer.status),
            ed2kHash: coreTransfer.ed2kHash,
            chunks: Self.chunks(progress: size == 0 ? 0 : Double(completed) / Double(size))
        )
    }

    nonisolated static func chunks(progress: Double) -> [ChunkState] {
        let total = 54
        let completed = Int((Double(total) * min(max(progress, 0), 1)).rounded(.down))

        return (0..<total).map { index in
            index < completed ? .complete : .missing
        }
    }
}

private extension SearchResult {
    nonisolated init(coreSearchResult: CoreSearchResult) {
        let size = min(coreSearchResult.sizeInBytes, UInt64(Int64.max))
        self.init(
            fileName: coreSearchResult.fileName,
            kind: FileKind.inferred(from: coreSearchResult.fileName),
            sizeInBytes: Int64(size),
            sources: coreSearchResult.sources,
            availability: coreSearchResult.availability,
            network: coreSearchResult.network,
            ed2kHash: coreSearchResult.ed2kHash,
            sourceClientID: coreSearchResult.sourceClientID,
            sourceClientPort: coreSearchResult.sourceClientPort
        )
    }
}

private extension FileKind {
    nonisolated init(coreKind: CoreFileKind) {
        switch coreKind {
        case .video: self = .video
        case .audio: self = .audio
        case .archive: self = .archive
        case .document: self = .document
        case .application: self = .application
        case .other: self = .other
        }
    }
}

private extension ServerSnapshot {
    nonisolated init(coreServer: CoreServer) {
        self.init(
            name: coreServer.name,
            address: coreServer.endpoint.address,
            users: coreServer.users,
            files: coreServer.files,
            pingMilliseconds: coreServer.pingMilliseconds,
            health: ServerHealth(coreStatus: coreServer.status),
            isPreferred: coreServer.isPreferred
        )
    }
}

private extension ServerHealth {
    nonisolated init(coreStatus: CoreServerStatus) {
        switch coreStatus {
        case .connected: self = .connected
        case .available: self = .available
        case .unavailable: self = .unavailable
        }
    }
}

private extension TransferStatus {
    nonisolated init(coreStatus: CoreTransferStatus) {
        switch coreStatus {
        case .queued: self = .queued
        case .downloading: self = .downloading
        case .paused: self = .paused
        case .verifying: self = .verifying
        case .completed: self = .completed
        case .failed: self = .failed
        }
    }
}

private extension NetworkSummary {
    nonisolated init(coreNetwork: CoreNetworkSummary) {
        self.init(
            isConnected: coreNetwork.isConnected,
            statusText: coreNetwork.statusText,
            downloadSpeedBytesPerSecond: Int64(min(coreNetwork.downloadSpeedBytesPerSecond, UInt64(Int64.max))),
            highID: coreNetwork.highID,
            kadNodes: coreNetwork.kadNodes,
            tcpPort: coreNetwork.tcpPort,
            udpPort: coreNetwork.udpPort
        )
    }
}

private extension SourceDetail {
    nonisolated init(corePeer: CorePeerInfo) {
        self.init(
            id: corePeer.id,
            clientName: corePeer.clientName,
            clientSoftware: corePeer.clientSoftware,
            ipAddress: corePeer.ipAddress,
            port: corePeer.port,
            state: SourceState(coreState: corePeer.state),
            queueRank: corePeer.queueRank,
            downloadSpeedBytesPerSecond: corePeer.downloadSpeedBytesPerSecond,
            partsAvailable: corePeer.partsAvailable,
            totalParts: max(corePeer.totalParts, 1),
            lastSeen: Date(),
            a4afFiles: [],
            score: corePeer.score
        )
    }
}

private extension SourceState {
    nonisolated init(coreState: CorePeerState) {
        switch coreState {
        case .connecting: self = .connecting
        case .onQueue: self = .onQueue
        case .downloading: self = .downloading
        case .noNeededParts: self = .noNeededParts
        case .tooManyConnections: self = .tooManyConnections
        case .banned: self = .banned
        case .error: self = .error
        case .unknown: self = .connecting
        }
    }
}
