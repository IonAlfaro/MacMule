import Foundation

public enum CoreServiceError: Error, Equatable, LocalizedError {
    case transferNotFound(String)
    case invalidTransferID(String)
    case serverNotFound(String)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .transferNotFound(let id):
            return "Transfer not found: \(id)."
        case .invalidTransferID(let id):
            return "Invalid transfer id: \(id)."
        case .serverNotFound(let address):
            return "Server not found: \(address)."
        case .persistence(let message):
            return "Transfer persistence failed: \(message)."
        }
    }
}

public final class MacMuleCoreService: @unchecked Sendable {
    private struct PeerDownloadPlan {
        var transferID: UUID
        var fileHash: Data
        var endpoint: ED2KPeerEndpoint
        var range: ED2KPartRange
    }

    private struct ServerCallbackRequest: Equatable {
        var transferID: UUID
        var fileHash: Data
        var sourceClientID: UInt32
        var sourceClientPort: UInt16
        var serverEndpoint: ED2KServerEndpoint?
    }

    private struct SourceLookupSendRequest {
        var transferID: UUID
        var fileHash: Data
        var fileSizeInBytes: UInt64
        var connection: ED2KServerTCPConnection
    }

    private struct PeerChunkRetryKey: Hashable {
        var startOffset: UInt64
        var endOffset: UInt64

        init(range: ED2KPartRange) {
            startOffset = range.startOffset
            endOffset = range.endOffset
        }

        var range: ED2KPartRange {
            ED2KPartRange(startOffset: startOffset, endOffset: endOffset)
        }
    }

    private struct PeerChunkRetryState {
        var failureCount: Int
        var cooldownUntil: Date?
        var lastFailureAt: Date
    }

    private struct PeerSpeedKey: Hashable {
        var transferID: UUID
        var endpoint: ED2KPeerEndpoint
    }

    private struct ByteRateTracker {
        private struct Sample {
            var timestamp: Date
            var bytes: UInt64
        }

        private static let rollingWindow: TimeInterval = 10.0
        private static let idleTimeout: TimeInterval = 3.0
        private static let minimumRateInterval: TimeInterval = 1.0

        private var samples: [Sample] = []
        private var lastDataAt: Date = .distantPast

        mutating func record(bytes: UInt64, at now: Date = Date()) -> UInt64 {
            if now.timeIntervalSince(lastDataAt) > Self.idleTimeout {
                samples.removeAll()
            }

            samples.append(Sample(timestamp: now, bytes: bytes))
            lastDataAt = now
            pruneSamples(at: now)
            return speed(at: now)
        }

        mutating func currentSpeed(at now: Date = Date()) -> UInt64 {
            pruneSamples(at: now)
            return speed(at: now)
        }

        func isIdle(at now: Date = Date()) -> Bool {
            now.timeIntervalSince(lastDataAt) > Self.idleTimeout
        }

        private mutating func pruneSamples(at now: Date) {
            let cutoff = now.addingTimeInterval(-Self.rollingWindow)
            samples.removeAll { $0.timestamp < cutoff }
        }

        private func speed(at now: Date) -> UInt64 {
            let idle = now.timeIntervalSince(lastDataAt)
            if idle > Self.idleTimeout { return 0 }

            let cutoff = now.addingTimeInterval(-Self.rollingWindow)
            let activeSamples = samples.filter { $0.timestamp >= cutoff }
            guard let first = activeSamples.first else { return 0 }

            let byteCount = activeSamples.reduce(UInt64(0)) { $0 + $1.bytes }
            let elapsed = max(now.timeIntervalSince(first.timestamp), Self.minimumRateInterval)
            return UInt64(Double(byteCount) / elapsed)
        }
    }

    private struct DatarateAverager {
        private struct Sample {
            var timestamp: Date
            var bytesPerSecond: UInt64
        }

        private static let rollingWindow: TimeInterval = 10.0
        private static let minimumSampleInterval: TimeInterval = 0.5

        private var samples: [Sample] = []
        private var totalBytesPerSecond: UInt64 = 0
        private var lastSampleAt: Date?

        mutating func record(bytesPerSecond: UInt64, at now: Date = Date()) -> UInt64 {
            if bytesPerSecond == 0 {
                samples.removeAll()
                totalBytesPerSecond = 0
                lastSampleAt = now
                return 0
            }

            pruneSamples(at: now)

            if let lastSampleAt,
               now.timeIntervalSince(lastSampleAt) < Self.minimumSampleInterval,
               let previous = samples.popLast() {
                totalBytesPerSecond = totalBytesPerSecond >= previous.bytesPerSecond
                    ? totalBytesPerSecond - previous.bytesPerSecond
                    : 0
            }

            samples.append(Sample(timestamp: now, bytesPerSecond: bytesPerSecond))
            totalBytesPerSecond += bytesPerSecond
            lastSampleAt = now
            pruneSamples(at: now)
            return average
        }

        mutating func currentAverage(at now: Date = Date()) -> UInt64 {
            pruneSamples(at: now)
            return average
        }

        private mutating func pruneSamples(at now: Date) {
            let cutoff = now.addingTimeInterval(-Self.rollingWindow)
            while let first = samples.first, first.timestamp < cutoff {
                totalBytesPerSecond = totalBytesPerSecond >= first.bytesPerSecond
                    ? totalBytesPerSecond - first.bytesPerSecond
                    : 0
                samples.removeFirst()
            }
        }

        private var average: UInt64 {
            guard samples.count > 1 else { return 0 }
            return totalBytesPerSecond / UInt64(samples.count)
        }
    }

    private static let peerRequestBlockSize: UInt64 = 256 * 1024
    private static let maxConcurrentPeerConnectionsPerTransfer = 2
    private static let peerInflightReservationTTL: TimeInterval = 30
    private static let peerFailureCooldownBase: TimeInterval = 15
    private static let peerFailureCooldownMax: TimeInterval = 120
    private static let maxSourceLookupRequestsPerPass = 15
    private static let emptySourceLookupRetryInterval: TimeInterval = 45
    private static let normalSourceLookupRetryInterval: TimeInterval = 10 * 60
    private static let sourceLookupMaintenanceInterval: TimeInterval = 30

    private var state: CoreSnapshot
    private let transferStore: CoreTransferStore?
    private let networkLogHandler: (@Sendable (String) -> Void)?
    private let serverTransportFactory: (@Sendable (ED2KServerEndpoint) -> ED2KServerTCPTransport)?
    private let peerTransportFactory: (@Sendable (ED2KPeerEndpoint) -> ED2KPeerTCPTransport)?
    private let peerListenerTransportFactory: (@Sendable (UInt16) -> ED2KPeerTCPListenerTransport)?
    private let peerPortMapper: ED2KPeerPortMapper?
    private var events: [CoreEvent] = []
    private var nextEventSequence: UInt64 = 1
    private var serverConnection: ED2KServerTCPConnection?
    private var serverConnectionGeneration: UInt64 = 0
    private var pendingServerConnectionStart: ED2KServerTCPConnection?
    private var peerListenerStartupTimeoutWorkItem: DispatchWorkItem?
    private var peerConnections: [UUID: [ED2KPeerEndpoint: ED2KPeerTCPConnection]] = [:]
    private var peerListener: ED2KPeerTCPListener?
    private var peerListenerPort: UInt16?
    private var isPeerListenerReady = false
    private var isServerSessionReady = false
    private var peerSourceQueues: [UUID: [ED2KPeerEndpoint]] = [:]
    private var peerSourceFailures: [UUID: [ED2KPeerEndpoint: Int]] = [:]
    private var peerSourceCooldowns: [UUID: [ED2KPeerEndpoint: Date]] = [:]
    private var peerInflightRanges: [UUID: [ED2KPeerEndpoint: ED2KPartRange]] = [:]
    private var peerInflightRangeTimestamps: [UUID: [ED2KPeerEndpoint: Date]] = [:]
    private var peerChunkRetryStates: [UUID: [PeerChunkRetryKey: PeerChunkRetryState]] = [:]
    private var peerPartHashSetRequestOwners: [UUID: ED2KPeerEndpoint] = [:]
    private var pendingServerCallbackRequests: [ServerCallbackRequest] = []
    private var activeServerCallbackRequest: ServerCallbackRequest?
    private var pendingSourceLookupTransferIDs: [UUID] = []
    private var sourceLookupLastRequestedAt: [UUID: Date] = [:]
    private var sourceLookupMaintenanceWorkItem: DispatchWorkItem?
    private var activeServerEndpoint: ED2KServerEndpoint?
    private var activeSearchQuery: String?
    private let clientUserHash: Data
    private let lock = NSLock()
    // Auto-reconnect
    private var reconnectConfiguration: ED2KServerSessionConfiguration?
    private var reconnectWorkItem: DispatchWorkItem?
    // Bandwidth limits (0 = unlimited)
    private var maxDownloadBytesPerSecond: UInt64 = 0
    private var maxUploadBytesPerSecond: UInt64 = 0
    // Real download speed tracking, mirroring eMule's source -> file -> queue flow.
    private var peerSpeedTrackers: [PeerSpeedKey: ByteRateTracker] = [:]
    private var directTransferSpeedTrackers: [UUID: ByteRateTracker] = [:]
    private var downloadQueueDatarateAverager = DatarateAverager()
    // Kad subsystem
    private var kadService: KadService?
    private var kadListener: KadUDPListener?
    private var kadPacketTracker: KadPacketTracker?
    private var kadSearchManager: KadSearchManager?
    private var kadIndexed: KadIndexed?
    private var kadNodesStore: KadNodesStore?
    private var kadPrefsStore: KadPrefsStore?
    private var kadRunning = false
    // eD2k UDP socket
    private var ed2kUDP: ED2KUDPListener?
    // Web interface
    private var webServer: CoreWebServer?
    private var webServerRunning = false
    // Known file list
    private var knownFileList: CoreKnownFileList?
    // Scheduler
    private var scheduler: CoreScheduler?
    // Upload, shared files, credits, filters — Tier 0 wired modules
    private var uploadQueue: CoreUploadQueue?
    private var sharedFileList: CoreSharedFileList?
    private var creditsList: CoreCreditsList?
    private var ipFilter: CoreIPFilter?
    private var corruptionBlackBox: CoreCorruptionBlackBox?
    private var rarityScheduler: CoreRarityScheduler?
    private static let peerListenerStartupTimeout: TimeInterval = 2

    public init(
        snapshot: CoreSnapshot = .empty,
        transferStore: CoreTransferStore? = nil,
        networkLogHandler: (@Sendable (String) -> Void)? = nil,
        serverTransportFactory: (@Sendable (ED2KServerEndpoint) -> ED2KServerTCPTransport)? = nil,
        peerTransportFactory: (@Sendable (ED2KPeerEndpoint) -> ED2KPeerTCPTransport)? = nil,
        peerListenerTransportFactory: (@Sendable (UInt16) -> ED2KPeerTCPListenerTransport)? = nil,
        peerPortMapper: ED2KPeerPortMapper? = nil
    ) {
        self.transferStore = transferStore
        self.networkLogHandler = networkLogHandler
        self.serverTransportFactory = serverTransportFactory
        self.peerTransportFactory = peerTransportFactory
        self.peerListenerTransportFactory = peerListenerTransportFactory
        self.peerPortMapper = peerPortMapper ?? (
            serverTransportFactory == nil &&
            peerTransportFactory == nil &&
            peerListenerTransportFactory == nil
                ? SequentialPeerPortMapper(
                    mappers: [
                        ("UPnP", UPnPPortMapper()),
                        ("NAT-PMP", NATPMPPortMapper())
                    ]
                )
                : nil
        )
        clientUserHash = Self.loadOrCreateClientUserHash(transferStore: transferStore)
        let persistedResumeCheckpoint = transferStore.flatMap { try? $0.loadResumeCheckpoint() }
        let hadUncleanShutdown = transferStore.flatMap { try? $0.activateRuntimeLock() } ?? false

        if snapshot == .empty,
           let transferStore,
           let persistedSnapshot = try? transferStore.loadSnapshot() {
            state = Self.normalizedPersistedSnapshot(persistedSnapshot)
        } else {
            state = snapshot
        }

        if hadUncleanShutdown {
            state = Self.normalizedCrashRecoveredSnapshot(
                state,
                checkpoint: persistedResumeCheckpoint
            )
            if let transferStore {
                for transfer in state.transfers {
                    try? transferStore.upsert(transfer)
                }
            }
        }
        activeSearchQuery = persistedResumeCheckpoint?.activeSearchQuery
        reconnectConfiguration = persistedResumeCheckpoint?.serverConfiguration
            .map { Self.normalizedServerSessionConfiguration($0.sessionConfiguration(userHash: clientUserHash)) }
        restorePersistedPeerSourceState()
        withLock {
            persistResumeCheckpointLocked()
        }
        // Tier 0 module initialization
        uploadQueue = CoreUploadQueue(maxActiveSlots: 5, maxUploadSpeed: maxUploadBytesPerSecond)
        sharedFileList = CoreSharedFileList()
        creditsList = CoreCreditsList()
        ipFilter = CoreIPFilter()
        corruptionBlackBox = CoreCorruptionBlackBox()
        rarityScheduler = CoreRarityScheduler()
        if let store = transferStore {
            let filterURL = store.rootDirectory.appendingPathComponent("ipfilter.dat")
            if FileManager.default.fileExists(atPath: filterURL.path) {
                try? ipFilter?.load(from: filterURL)
            }
            let knownURL = store.rootDirectory.appendingPathComponent("known.json")
            let known = CoreKnownFileList(fileURL: knownURL)
            try? known.load()
            knownFileList = known
        }
        // Scheduler
        if let store = transferStore {
            let schedURL = store.rootDirectory.appendingPathComponent("scheduler.json")
            let sched = CoreScheduler(
                fileURL: schedURL,
                actionHandler: { [weak self] action in
                    self?.handleSchedulerAction(action)
                },
                logHandler: { [weak self] msg in self?.networkLogHandler?(msg) }
            )
            try? sched.load()
            if sched.enabled { sched.start() }
            scheduler = sched
        }
    }

    deinit {
        try? knownFileList?.save()
        scheduler?.stop()
        webServer?.stop()
        kadListener?.stop()
        kadService?.stop()
        ed2kUDP?.stop()
        sourceLookupMaintenanceWorkItem?.cancel()
        peerListener?.cancel()
        try? transferStore?.clearRuntimeLock()
    }

    public func snapshot() -> CoreSnapshot {
        withLock {
            let s = buildSnapshotWithKad()
            state.kad = s.kad
            state.transferPeers = s.transferPeers
            return s
        }
    }

    public func userHash() -> Data {
        clientUserHash
    }

    public func preferredServerEndpoint() -> ED2KServerEndpoint? {
        let endpoint = withLock {
            preferredAvailableServerEndpointLocked()
        }
        if let endpoint {
            emitNetworkLog("Preferred server: \(endpoint.host):\(endpoint.port)")
        } else {
            emitNetworkLog("No preferred server available")
        }
        return endpoint
    }

    public func events(after sequence: UInt64) -> CoreEventBatch {
        withLock {
            CoreEventBatch(
                afterSequence: sequence,
                latestSequence: nextEventSequence - 1,
                events: events.filter { $0.sequence > sequence },
                snapshot: buildSnapshotWithKad()
            )
        }
    }

    public func kadStart() -> CoreSnapshot {
        withLock {
            guard !kadRunning else { return buildSnapshotWithKad() }

            let kadPrefsURL = transferStore?.rootDirectory
                .appendingPathComponent("preferencesKad.json") ?? URL(fileURLWithPath: "/tmp/macmule_kad_prefs.json")
            let kadNodesURL = transferStore?.rootDirectory
                .appendingPathComponent("nodes.dat") ?? URL(fileURLWithPath: "/tmp/macmule_nodes.dat")

            kadPrefsStore = KadPrefsStore(fileURL: kadPrefsURL)
            kadNodesStore = KadNodesStore(fileURL: kadNodesURL)

            let prefs = (try? kadPrefsStore?.load()) ?? KadPreferences()
            let selfNodeID = prefs.lastSelfNodeID

            kadService = KadService(selfNodeID: selfNodeID, logHandler: { [weak self] message in
                self?.networkLogHandler?(message)
            })
            kadListener = KadUDPListener(logHandler: { [weak self] message in
                self?.networkLogHandler?(message)
            })
            kadPacketTracker = KadPacketTracker()
            kadSearchManager = KadSearchManager()
            kadIndexed = KadIndexed()

            // Wire KadPacketHandler and KadClientSearcher
            if let kadService, let kadListener, let kadPacketTracker, let kadSearchManager, let kadIndexed {
                let packetHandler = KadPacketHandler(
                    service: kadService,
                    indexed: kadIndexed,
                    listener: kadListener,
                    packetTracker: kadPacketTracker,
                    searchManager: kadSearchManager,
                    logHandler: { [weak self] msg in self?.networkLogHandler?("[Kad] \(msg)") }
                )
                kadListener.setPacketHandler(packetHandler)

                // Wire KadClientSearcher into KadService for real network operations
                let searcher = KadClientSearcher(
                    routingTable: kadService.routingTable,
                    listener: kadListener,
                    packetTracker: kadPacketTracker,
                    logHandler: { [weak self] msg in self?.networkLogHandler?("[Kad] \(msg)") }
                )
                kadService.clientSearcher = searcher

                // Wire KadLookupCoordinator for iterative Kad lookups
                let lookups = KadLookupCoordinator(
                    routingTable: kadService.routingTable,
                    clientSearcher: searcher,
                    logHandler: { [weak self] msg in self?.networkLogHandler?("[Kad] \(msg)") }
                )
                kadService.lookups = lookups
            }

            do {
                try kadListener?.start(port: prefs.kadPort)
            } catch {
                networkLogHandler?("Kad UDP listener failed to start: \(error)")
            }

            kadService?.start()

            if let savedNodes = try? kadNodesStore?.loadNodes() {
                for node in savedNodes {
                    kadService?.addContact(node)
                }
            }

            kadRunning = true
            networkLogHandler?("Kad started with \(kadService?.nodeCount ?? 0) known nodes")

            Task.detached { [weak self] in
                await self?.kadService?.bootstrap(from: prefs.bootstrapNodes)
                self?.withLock {
                    self?.state.kad = self?.buildKadSummary() ?? CoreKadSummary()
                    self?.recordKadUpdateLocked()
                }
            }

            return buildSnapshotWithKad()
        }
    }

    public func kadStop() -> CoreSnapshot {
        withLock {
            guard kadRunning else { return buildSnapshotWithKad() }

            kadService?.stop()
            kadListener?.stop()
            kadPacketTracker?.cancelAll()
            kadRunning = false
            networkLogHandler?("Kad stopped")
            return buildSnapshotWithKad()
        }
    }

    public func kadBootstrap(ip: String, port: UInt16) -> CoreSnapshot {
        withLock {
            guard let service = kadService else { return buildSnapshotWithKad() }

            let endpoint = KadEndpoint(ipAddress: ip, port: port)
            Task.detached { [weak self] in
                await service.bootstrap(from: [endpoint])
                self?.withLock {
                    self?.state.kad = self?.buildKadSummary() ?? CoreKadSummary()
                    self?.recordKadUpdateLocked()
                }
            }

            return buildSnapshotWithKad()
        }
    }

    public func kadSearchKeyword(query: String) -> CoreSnapshot {
        withLock {
            guard let service = kadService,
                  let indexed = kadIndexed,
                  let searchManager = kadSearchManager,
                  kadRunning else {
                return buildSnapshotWithKad()
            }

            let searchID = KadUInt128.random()
            let target = KadUInt128(data: Data(query.utf8.prefix(16)))
            _ = searchManager.startSearch(
                id: searchID,
                type: .keyword,
                target: target,
                searchTerms: Data(query.utf8)
            )

            // Perform real iterative Kad lookup in background
            let lookupRef = kadService?.lookups
            if let lookupRef {
                Task.detached { [weak self] in
                    let closest = await lookupRef.findNodes(target: target)
                    self?.networkLogHandler?("Kad: keyword search '\(query)' found \(closest.count) closest nodes")
                }
            }

            let localResults = indexed.searchKeyword(query)
            for result in localResults {
                state.searchResults.append(
                    CoreSearchResult(
                        fileName: result.fileName,
                        sizeInBytes: result.fileSize,
                        sources: 1,
                        network: "Kad",
                        ed2kHash: result.fileHash.map { String(format: "%02X", $0) }.joined()
                    )
                )
            }

            if !localResults.isEmpty {
                recordKadSearchResultLocked()
            }

            networkLogHandler?("Kad keyword search started for: \(query)")
            return buildSnapshotWithKad()
        }
    }

    public func kadSearchSources(hash: String) -> CoreSnapshot {
        withLock {
            guard let service = kadService,
                  let indexed = kadIndexed,
                  let searchManager = kadSearchManager,
                  kadRunning,
                  let fileHash = Data(hexadecimalString: hash) else {
                return buildSnapshotWithKad()
            }

            let searchID = KadUInt128.random()
            let target = KadUInt128(data: fileHash)
            _ = searchManager.startSearch(
                id: searchID,
                type: .source,
                target: target
            )

            let localResults = indexed.searchSources(fileHash: fileHash)
            for result in localResults {
                if let transferIndex = state.transfers.firstIndex(where: { $0.ed2kHash == hash }) {
                    state.transfers[transferIndex].sources += 1
                }
            }

            // Perform real iterative Kad source lookup in background
            let lookupRef = kadService?.lookups
            if let lookupRef {
                Task.detached { [weak self] in
                    let closest = await lookupRef.findNodes(target: target)
                    self?.networkLogHandler?("Kad: source search for hash '\(hash.prefix(8))' found \(closest.count) closest nodes")
                }
            }

            if !localResults.isEmpty {
                recordKadSearchResultLocked()
            }

            networkLogHandler?("Kad source search started for hash: \(hash)")
            return buildSnapshotWithKad()
        }
    }

    public func kadPublishKeyword(fileHash: Data, fileName: String, fileSize: UInt64) {
        guard let indexed = kadIndexed, kadRunning else { return }

        indexed.addKeyword(
            keyword: fileName,
            fileHash: fileHash,
            fileName: fileName,
            fileSize: fileSize,
            sourceID: kadService?.selfNodeID ?? KadUInt128()
        )
    }

    public func kadPublishSource(fileHash: Data, fileName: String, fileSize: UInt64, ipAddress: String, port: UInt16) {
        guard let indexed = kadIndexed, kadRunning else { return }

        let contact = KadContact(
            nodeID: kadService?.selfNodeID ?? KadUInt128(),
            ipAddress: ipAddress,
            udpPort: port,
            tcpPort: port
        )
        indexed.addSource(
            fileHash: fileHash,
            contact: contact,
            fileName: fileName,
            fileSize: fileSize
        )
    }

    public func webStart(port: UInt16, password: String = "") -> CoreSnapshot {
        withLock {
            guard !webServerRunning else { return buildSnapshotWithKad() }
            let server = CoreWebServer(
                serviceProvider: { [weak self] in self?.snapshot() ?? .empty },
                commandHandler: { [weak self] cmd, params in
                    guard let self = self else { return nil }
                    let req = JSONRPCRequest(method: cmd, params: params.isEmpty ? nil : params)
                    let rpc = CoreRPCHandler(service: self)
                    let response = rpc.handle(req)
                    return response.result?.snapshot
                },
                logHandler: { [weak self] msg in self?.networkLogHandler?(msg) }
            )
            do {
                try server.start(port: port, password: password)
                webServer = server
                webServerRunning = true
                networkLogHandler?("Web interface started on port \(port)")
            } catch {
                networkLogHandler?("Web interface failed: \(error)")
            }
            return buildSnapshotWithKad()
        }
    }

    public func webStop() -> CoreSnapshot {
        withLock {
            webServer?.stop()
            webServer = nil
            webServerRunning = false
            return buildSnapshotWithKad()
        }
    }

    public func schedulerEnable(_ enabled: Bool) -> CoreSnapshot {
        withLock {
            scheduler?.enabled = enabled
            if enabled {
                scheduler?.start()
            } else {
                scheduler?.stop()
            }
            try? scheduler?.save()
            networkLogHandler?("Scheduler \(enabled ? "enabled" : "disabled")")
            return buildSnapshotWithKad()
        }
    }

    public func schedulerAddEntry(_ entry: ScheduleEntry) -> CoreSnapshot {
        withLock {
            scheduler?.addEntry(entry)
            return buildSnapshotWithKad()
        }
    }

    public func schedulerRemoveEntry(id: UUID) -> CoreSnapshot {
        withLock {
            scheduler?.removeEntry(id: id)
            return buildSnapshotWithKad()
        }
    }

    public func schedulerEntries() -> [ScheduleEntry] {
        scheduler?.allEntries() ?? []
    }

    private func handleSchedulerAction(_ action: ScheduleAction) {
        withLock {
            switch action.type {
            case .setUploadLimit:
                if let value = UInt64(action.value) {
                    maxUploadBytesPerSecond = value * 1024
                    networkLogHandler?("Scheduler: upload limit set to \(value) KB/s")
                }
            case .setDownloadLimit:
                if let value = UInt64(action.value) {
                    maxDownloadBytesPerSecond = value * 1024
                    networkLogHandler?("Scheduler: download limit set to \(value) KB/s")
                }
            case .disconnect:
                disconnectServer()
            case .connect:
                reconnectConfiguration.map { _ = connectToServer($0) }
            default:
                networkLogHandler?("Scheduler: action \(action.type.rawValue) = \(action.value)")
            }
        }
    }

    private func buildKadSummary() -> CoreKadSummary {
        CoreKadSummary(
            isRunning: kadRunning,
            isConnected: kadService?.isConnected ?? false,
            isFirewalled: kadService?.isFirewalled ?? true,
            nodeCount: kadService?.nodeCount ?? 0,
            activeSearchCount: kadSearchManager?.activeSearchCount ?? 0,
            totalKeywords: kadIndexed?.stats.keywordCount ?? 0,
            totalSources: kadIndexed?.stats.sourceCount ?? 0
        )
    }

    private func buildSnapshotWithKad() -> CoreSnapshot {
        let now = Date()
        let transferSpeeds = refreshDownloadSpeedsLocked(at: now)
        let queueDatarate = transferSpeeds.values.reduce(UInt64(0)) { $0 + $1 }
        var s = state
        for i in s.transfers.indices {
            s.transfers[i].downloadSpeedBytesPerSecond = transferSpeeds[s.transfers[i].id, default: 0]
        }
        s.network.downloadSpeedBytesPerSecond = downloadQueueDatarateAverager.record(
            bytesPerSecond: queueDatarate,
            at: now
        )
        s.kad = buildKadSummary()
        s.transferPeers = buildPeerInfoLocked(at: now)
        return s
    }

    private func buildPeerInfoLocked(at now: Date = Date()) -> [UUID: [CorePeerInfo]] {
        var result: [UUID: [CorePeerInfo]] = [:]
        var transferIDs = Set(peerSourceQueues.keys)
        transferIDs.formUnion(peerConnections.keys)
        transferIDs.formUnion(peerSpeedTrackers.keys.map(\.transferID))

        for transferID in transferIDs {
            let queuedEndpoints = peerSourceQueues[transferID] ?? []
            let activeEndpoints = peerConnections[transferID].map { Array($0.keys) } ?? []
            let measuredEndpoints = peerSpeedTrackers.keys
                .filter { $0.transferID == transferID }
                .map(\.endpoint)
            let endpoints = orderedUniqueEndpoints(activeEndpoints + queuedEndpoints + measuredEndpoints)
            var peers: [CorePeerInfo] = []
            for endpoint in endpoints.prefix(10) {
                let speed = currentDownloadSpeedLocked(for: transferID, endpoint: endpoint, at: now)
                let info = CorePeerInfo(
                    ipAddress: endpoint.host,
                    port: Int(endpoint.port),
                    clientName: "eMule client",
                    clientSoftware: "eMule",
                    state: peerStateLocked(for: transferID, endpoint: endpoint, speed: speed),
                    downloadSpeedBytesPerSecond: Int64(min(speed, UInt64(Int64.max))),
                    queueRank: 0,
                    score: 1.0
                )
                peers.append(info)
            }
            result[transferID] = peers
        }
        return result
    }

    private func orderedUniqueEndpoints(_ endpoints: [ED2KPeerEndpoint]) -> [ED2KPeerEndpoint] {
        var seen = Set<ED2KPeerEndpoint>()
        var unique: [ED2KPeerEndpoint] = []
        for endpoint in endpoints where seen.insert(endpoint).inserted {
            unique.append(endpoint)
        }
        return unique
    }

    private func peerStateLocked(
        for transferID: UUID,
        endpoint: ED2KPeerEndpoint,
        speed: UInt64
    ) -> CorePeerState {
        if speed > 0 {
            return .downloading
        }
        if peerConnections[transferID]?[endpoint] != nil {
            return peerInflightRanges[transferID]?[endpoint] == nil ? .connecting : .downloading
        }
        if peerSourceCooldowns[transferID]?[endpoint].map({ $0 > Date() }) == true {
            return .error
        }
        return .onQueue
    }

    private func refreshDownloadSpeedsLocked(at now: Date = Date()) -> [UUID: UInt64] {
        var transferIDs = Set(state.transfers.map(\.id))
        transferIDs.formUnion(peerSpeedTrackers.keys.map(\.transferID))
        transferIDs.formUnion(directTransferSpeedTrackers.keys)

        var speeds: [UUID: UInt64] = [:]
        for transferID in transferIDs {
            speeds[transferID] = currentDownloadSpeedLocked(for: transferID, at: now)
        }
        return speeds
    }

    private func recordDownloadBytesLocked(
        transferID: UUID,
        sourceEndpoint: ED2KPeerEndpoint?,
        byteCount: UInt64,
        at now: Date = Date()
    ) -> UInt64 {
        if let sourceEndpoint {
            let key = PeerSpeedKey(transferID: transferID, endpoint: sourceEndpoint)
            var tracker = peerSpeedTrackers[key, default: ByteRateTracker()]
            _ = tracker.record(bytes: byteCount, at: now)
            peerSpeedTrackers[key] = tracker
        } else {
            var tracker = directTransferSpeedTrackers[transferID, default: ByteRateTracker()]
            _ = tracker.record(bytes: byteCount, at: now)
            directTransferSpeedTrackers[transferID] = tracker
        }

        return currentDownloadSpeedLocked(for: transferID, at: now)
    }

    private func currentDownloadSpeedLocked(for transferID: UUID, at now: Date = Date()) -> UInt64 {
        var total: UInt64 = 0
        for key in Array(peerSpeedTrackers.keys) where key.transferID == transferID {
            total += currentDownloadSpeedLocked(for: transferID, endpoint: key.endpoint, at: now)
        }

        if var tracker = directTransferSpeedTrackers[transferID] {
            let speed = tracker.currentSpeed(at: now)
            if tracker.isIdle(at: now) {
                directTransferSpeedTrackers.removeValue(forKey: transferID)
            } else {
                directTransferSpeedTrackers[transferID] = tracker
            }
            total += speed
        }

        return total
    }

    private func currentDownloadSpeedLocked(
        for transferID: UUID,
        endpoint: ED2KPeerEndpoint,
        at now: Date = Date()
    ) -> UInt64 {
        let key = PeerSpeedKey(transferID: transferID, endpoint: endpoint)
        guard var tracker = peerSpeedTrackers[key] else {
            return 0
        }

        let speed = tracker.currentSpeed(at: now)
        if tracker.isIdle(at: now) {
            peerSpeedTrackers.removeValue(forKey: key)
        } else {
            peerSpeedTrackers[key] = tracker
        }
        return speed
    }

    private func removeDownloadSpeedStateLocked(for transferID: UUID) {
        directTransferSpeedTrackers.removeValue(forKey: transferID)
        for key in Array(peerSpeedTrackers.keys) where key.transferID == transferID {
            peerSpeedTrackers.removeValue(forKey: key)
        }
    }

    @discardableResult
    public func addED2KLink(_ rawLink: String) throws -> CoreSnapshot {
        let link = try ED2KLinkParser.parseFileLink(rawLink)
        return try addED2KLink(link)
    }

    @discardableResult
    public func addED2KLink(
        _ link: ED2KFileLink,
        initialSources: [ED2KFoundSource] = []
    ) throws -> CoreSnapshot {
        guard checkDiskSpace(for: link.sizeInBytes) else {
            emitNetworkLog("No hay suficiente espacio en disco para: \(link.fileName)")
            return snapshot()
        }
        let (snapshot, transfer) = try withLock {
            guard let fileHash = Data(hexadecimalString: link.hash) else {
                throw CoreServiceError.persistence("Invalid ED2K hash in link: \(link.hash)")
            }

            if let existingIndex = state.transfers.firstIndex(where: { $0.ed2kHash == link.hash }) {
                let existing = state.transfers.remove(at: existingIndex)
                state.transfers.insert(existing, at: 0)
                applyInitialSourcesLocked(initialSources, fileHash: fileHash, transferID: existing.id)
                let updated = state.transfers[0]
                try persist(updated)
                recordLocked(.transferUpdated, transfer: updated)
                return (state, updated)
            }

            let createdTransfer = CoreTransfer(
                fileName: link.fileName,
                kind: CoreFileKind.inferred(from: link.fileName),
                sizeInBytes: link.sizeInBytes,
                status: .queued,
                ed2kHash: link.hash,
                rootHash: link.rootHash,
                partHashes: link.partHashes
            )
            state.transfers.insert(createdTransfer, at: 0)
            try persist(createdTransfer)
            applyInitialSourcesLocked(initialSources, fileHash: fileHash, transferID: createdTransfer.id)
            let updated = state.transfers[0]
            try persist(updated)
            recordLocked(.transferAdded, transfer: updated)
            if let hashData = Data(hexadecimalString: updated.ed2kHash) {
                knownFileList?.recordDownload(hash: hashData, fileName: updated.fileName, fileSize: updated.sizeInBytes)
                try? knownFileList?.save()
            }
            return (state, updated)
        }

        requestServerCallbacksIfPossible()
        requestSourcesIfPossible(for: transfer, force: true)
        startPeerDownloadsIfPossible(for: transfer.id)
        return snapshot
    }

    @discardableResult
    public func pauseTransfer(id rawID: String) throws -> CoreSnapshot {
        let transferID = try parseTransferID(rawID)
        let snapshot = try updateTransfer(id: rawID) { transfer in
            guard transfer.status != .completed else { return }
            transfer.status = .paused
            transfer.downloadSpeedBytesPerSecond = 0
        }
        cancelPeerConnections(for: transferID)
        withLock {
            removeDownloadSpeedStateLocked(for: transferID)
            removeSourceLookupStateLocked(for: transferID)
        }
        return snapshot
    }

    @discardableResult
    public func resumeTransfer(id rawID: String) throws -> CoreSnapshot {
        let transferID = try parseTransferID(rawID)
        let snapshot = try updateTransfer(id: rawID) { transfer in
            guard transfer.status != .completed else { return }
            transfer.status = .queued
            transfer.downloadSpeedBytesPerSecond = 0
        }
        withLock {
            removeDownloadSpeedStateLocked(for: transferID)
        }
        if let transfer = snapshot.transfers.first(where: { $0.id == transferID }) {
            requestSourcesIfPossible(for: transfer, force: true)
            startPeerDownloadsIfPossible(for: transferID)
        }
        return snapshot
    }

    @discardableResult
    public func removeTransfer(id rawID: String) throws -> CoreSnapshot {
        let id = try parseTransferID(rawID)
        let snapshot = try withLock {
            guard let index = state.transfers.firstIndex(where: { $0.id == id }) else {
                throw CoreServiceError.transferNotFound(rawID)
            }
            let removed = state.transfers.remove(at: index)
            removeDownloadSpeedStateLocked(for: id)
            try removePersistedTransfer(removed)
            recordLocked(.transferRemoved, transfer: removed)
            if let hashData = Data(hexadecimalString: removed.ed2kHash) {
                knownFileList?.markCancelled(hash: hashData)
                try? knownFileList?.save()
            }
            return state
        }
        cancelPeerConnections(for: id)
        withLock {
            peerSourceQueues.removeValue(forKey: id)
            peerSourceFailures.removeValue(forKey: id)
            peerSourceCooldowns.removeValue(forKey: id)
            peerInflightRanges.removeValue(forKey: id)
            peerInflightRangeTimestamps.removeValue(forKey: id)
            peerChunkRetryStates.removeValue(forKey: id)
            removeSourceLookupStateLocked(for: id)
            pendingServerCallbackRequests.removeAll { $0.transferID == id }
            if activeServerCallbackRequest?.transferID == id {
                activeServerCallbackRequest = nil
            }
        }
        return snapshot
    }

    @discardableResult
    public func setConfig(maxDownloadKbps: Int, maxUploadKbps: Int) -> CoreSnapshot {
        withLock {
            maxDownloadBytesPerSecond = maxDownloadKbps > 0 ? UInt64(maxDownloadKbps) * 1024 : 0
            maxUploadBytesPerSecond = maxUploadKbps > 0 ? UInt64(maxUploadKbps) * 1024 : 0
            emitNetworkLog("Config: down \(maxDownloadKbps) KB/s, up \(maxUploadKbps) KB/s")
            return state
        }
    }

    @discardableResult
    public func writeBlock(id rawID: String, offset: UInt64, data: Data) throws -> CoreSnapshot {
        return try writeBlock(id: rawID, offset: offset, data: data, sourceEndpoint: nil)
    }

    @discardableResult
    private func writeBlock(
        id rawID: String,
        offset: UInt64,
        data: Data,
        sourceEndpoint: ED2KPeerEndpoint?
    ) throws -> CoreSnapshot {
        let id = try parseTransferID(rawID)
        let byteCount = UInt64(data.count)
        return try withLock {
            guard let index = state.transfers.firstIndex(where: { $0.id == id }) else {
                throw CoreServiceError.transferNotFound(rawID)
            }

            guard let transferStore else {
                throw CoreServiceError.persistence("No transfer store configured.")
            }

            let previous = state.transfers[index]
            let transferRecord = try transferStore.writeBlock(transferID: id, offset: offset, data: data)
            state.transfers[index] = transferRecord.transfer
            if state.transfers[index].status == .queued {
                state.transfers[index].status = .downloading
                try? persist(state.transfers[index])
            }

            // Track real download speed from the actual source when available.
            if state.transfers[index].status == .downloading {
                let now = Date()
                let speed = recordDownloadBytesLocked(
                    transferID: id,
                    sourceEndpoint: sourceEndpoint,
                    byteCount: byteCount,
                    at: now
                )
                state.transfers[index].downloadSpeedBytesPerSecond = speed
                let queueDatarate = refreshDownloadSpeedsLocked(at: now).values.reduce(UInt64(0)) { $0 + $1 }
                state.network.downloadSpeedBytesPerSecond = downloadQueueDatarateAverager.record(
                    bytesPerSecond: queueDatarate,
                    at: now
                )
            } else {
                let now = Date()
                removeDownloadSpeedStateLocked(for: id)
                state.transfers[index].downloadSpeedBytesPerSecond = 0
                let queueDatarate = refreshDownloadSpeedsLocked(at: now).values.reduce(UInt64(0)) { $0 + $1 }
                state.network.downloadSpeedBytesPerSecond = downloadQueueDatarateAverager.record(
                    bytesPerSecond: queueDatarate,
                    at: now
                )
            }

            if transferRecord.transfer.status == .failed {
                if let hashData = Data(hexadecimalString: state.transfers[index].ed2kHash) {
                    corruptionBlackBox?.recordCorruptChunk(
                        fileHash: hashData,
                        offset: offset,
                        length: byteCount,
                        sourceID: KadUInt128()
                    )
                }
                handleCorruptChunk(for: id, offset: offset, length: byteCount)
            }

            creditsList?.addDownloadBytes(byteCount, for: Data())

            if state.transfers[index] != previous {
                recordLocked(.transferUpdated, transfer: state.transfers[index])
            }

            if transferRecord.transfer.status == .completed {
                try finalizeTransferLocked(id: id)
            }

            return state
        }
    }

    @discardableResult
    public func completeTransferAndPromote(id rawID: String) throws -> CoreSnapshot {
        let id = try parseTransferID(rawID)
        return try withLock {
            guard let index = state.transfers.firstIndex(where: { $0.id == id }) else {
                throw CoreServiceError.transferNotFound(rawID)
            }
            guard state.transfers[index].status == .completed else {
                emitNetworkLog("completeTransferAndPromote: transfer \(rawID) is not completed")
                return state
            }
            try finalizeTransferLocked(id: id)
            return state
        }
    }

    private func finalizeTransferLocked(id: UUID) throws {
        guard let index = state.transfers.firstIndex(where: { $0.id == id }),
              let transferStore else {
            return
        }

        let transfer = state.transfers[index]
        guard transfer.status == .completed else { return }

        let record = try transferStore.loadRecord(for: id)
        guard let completedFileName = record.completedFileName else {
            emitNetworkLog("finalizeTransferLocked: transfer \(id) has no completed file name")
            return
        }

        let completedFileURL = transferStore.incomingDirectory.appendingPathComponent(completedFileName)

        if let hashData = Data(hexadecimalString: transfer.ed2kHash) {
            let entry = CoreSharedFileList.SharedFileEntry(
                filePath: completedFileURL.path,
                fileName: completedFileName,
                fileSize: transfer.sizeInBytes,
                ed2kHash: hashData,
                partHashes: transfer.partHashes.compactMap { Data(hexadecimalString: $0) }
            )
            sharedFileList?.addFile(entry)

            knownFileList?.recordDownload(hash: hashData, fileName: transfer.fileName, fileSize: transfer.sizeInBytes)
            try? knownFileList?.save()
        }

        do {
            let metadataURL = transferStore.metadataURL(for: id)
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                try FileManager.default.removeItem(at: metadataURL)
            }
        } catch {
            emitNetworkLog("finalizeTransferLocked: failed to remove metadata: \(error.localizedDescription)")
        }

        emitNetworkLog("Transfer \(id) completed and promoted: \(transfer.fileName)")
    }

    private func requestAICHRecovery(for transferID: UUID) {
        // For now, just mark the corrupt chunk as missing so it can be re-downloaded
        // A full implementation would use the root hash to recover from other parts
    }

    private func handleCorruptChunk(for transferID: UUID, offset: UInt64, length: UInt64) {
        requestAICHRecovery(for: transferID)
        guard let transferStore else { return }
        do {
            var record = try transferStore.loadRecord(for: transferID)
            record.chunkMap.clearWritten(offset: offset, length: length)
            record.transfer.completedBytes = record.chunkMap.completedBytes
            try transferStore.upsert(record.transfer)
        } catch {
            emitNetworkLog("AICH recovery: failed to handle corrupt chunk: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func connectToServer(
        _ configuration: ED2KServerSessionConfiguration,
        transport: ED2KServerTCPTransport? = nil
    ) -> CoreSnapshot {
        let configuration = Self.normalizedServerSessionConfiguration(
            configuration
        )

        // Store for auto-reconnect and cancel any pending reconnect attempt
        let (pendingWorkItem, connectionGeneration) = withLock {
            let item = reconnectWorkItem
            reconnectWorkItem = nil
            reconnectConfiguration = configuration
            serverConnectionGeneration &+= 1
            return (item, serverConnectionGeneration)
        }
        pendingWorkItem?.cancel()

        if ipFilter?.isBlocked(ip: configuration.endpoint.host) == true {
            emitNetworkLog("eD2k connect blocked by IP filter: \(configuration.endpoint.host)")
            return snapshot()
        }

        // Start eD2k UDP listener for server status/sources
        if ed2kUDP == nil {
            let udpListener = ED2KUDPListener(logHandler: { [weak self] msg in
                self?.emitNetworkLog(msg)
            })
            let udpPort = configuration.tcpPort > 0 ? configuration.tcpPort + 10 : 4672
            try? udpListener.start(port: UInt16(udpPort))
            ed2kUDP = udpListener
        }

        let resolvedTransport = transport
            ?? serverTransportFactory?(configuration.endpoint)
            ?? NetworkED2KServerTCPTransport(endpoint: configuration.endpoint)
        resolvedTransport.logHandler = { [weak self] msg in
            self?.emitNetworkLog(msg)
        }
        let connection = ED2KServerTCPConnection(
            configuration: configuration,
            transport: resolvedTransport
        ) { [weak self] event in
            self?.applyServerConnectionEvent(
                event,
                endpoint: configuration.endpoint,
                generation: connectionGeneration
            )
        }
        var listenerToStart: ED2KPeerTCPListener?
        var listenerToCancel: ED2KPeerTCPListener?
        var shouldWaitForPeerListenerBeforeServerLogin = false

        let snapshot = withLock {
            peerListenerStartupTimeoutWorkItem?.cancel()
            peerListenerStartupTimeoutWorkItem = nil
            pendingServerConnectionStart = nil
            serverConnection?.cancel()
            serverConnection = connection
            isServerSessionReady = false
            let needsPeerListener = peerListenerPort != configuration.tcpPort || peerListener == nil
            if needsPeerListener {
                let resolvedPeerListenerTransport: ED2KPeerTCPListenerTransport
                if let peerListenerTransportFactory {
                    resolvedPeerListenerTransport = peerListenerTransportFactory(configuration.tcpPort)
                } else if transport != nil || serverTransportFactory != nil {
                    resolvedPeerListenerTransport = NoopED2KPeerTCPListenerTransport()
                } else {
                    resolvedPeerListenerTransport = NetworkED2KPeerTCPListenerTransport(port: configuration.tcpPort)
                }

                let nextPeerListener = ED2KPeerTCPListener(
                    configuration: makePeerListenerConfiguration(for: configuration),
                    transport: resolvedPeerListenerTransport
                ) { [weak self] event in
                    self?.applyPeerListenerEvent(event)
                }

                listenerToCancel = peerListener
                peerListener = nextPeerListener
                peerListenerPort = configuration.tcpPort
                isPeerListenerReady = false
                listenerToStart = nextPeerListener
            }
            shouldWaitForPeerListenerBeforeServerLogin = false
            pendingServerConnectionStart = connection
            activeServerEndpoint = nil
            setPreferredServerLocked(configuration.endpoint)
            updateNetworkPortsLocked(tcpPort: Int(configuration.tcpPort))
            let statusText = "Connecting to \(configuration.endpoint.address)"
            updateNetworkLocked(
                isConnected: false,
                statusText: statusText,
                highID: false,
                kadNodes: 0
            )
            emitNetworkLog("eD2k connect requested: \(configuration.endpoint.address)")
            return state
        }

        listenerToCancel?.cancel()
        listenerToStart?.start()
        if shouldWaitForPeerListenerBeforeServerLogin {
            schedulePeerListenerStartupTimeout(for: connection, endpoint: configuration.endpoint)
        } else {
            connection.start()
        }
        return snapshot
    }

    @discardableResult
    public func disconnectServer() -> CoreSnapshot {
        // User-initiated disconnect: clear reconnect config
        let pendingWorkItem = withLock {
            let item = reconnectWorkItem
            reconnectWorkItem = nil
            reconnectConfiguration = nil
            return item
        }
        pendingWorkItem?.cancel()

        return withLock {
            peerListenerStartupTimeoutWorkItem?.cancel()
            peerListenerStartupTimeoutWorkItem = nil
            sourceLookupMaintenanceWorkItem?.cancel()
            sourceLookupMaintenanceWorkItem = nil
            pendingSourceLookupTransferIDs.removeAll()
            pendingServerConnectionStart = nil
            serverConnectionGeneration &+= 1
            serverConnection?.cancel()
            serverConnection = nil
            ed2kUDP?.stop()
            isServerSessionReady = false
            activeSearchQuery = nil
            if state.searchResults.isEmpty == false {
                state.searchResults.removeAll()
                recordNetworkUpdateLocked()
            }
            updateServerStatusesLocked(connectedEndpoint: nil)
            updateNetworkLocked(
                isConnected: false,
                statusText: "Offline",
                highID: false,
                kadNodes: 0
            )
            emitNetworkLog("eD2k disconnected.")
            return state
        }
    }

    @discardableResult
    public func addServer(endpoint: ED2KServerEndpoint, name: String? = nil) throws -> CoreSnapshot {
        try withLock {
            let existingIndex = state.servers.firstIndex { $0.endpoint == endpoint }
            if let existingIndex {
                if let name, name.isEmpty == false, state.servers[existingIndex].name != name {
                    state.servers[existingIndex].name = name
                    try persistServers()
                    recordNetworkUpdateLocked()
                }
                return state
            }

            state.servers.append(
                CoreServer(
                    endpoint: endpoint,
                    name: name,
                    isPreferred: state.servers.contains(where: \.isPreferred) == false
                )
            )
            try persistServers()
            recordNetworkUpdateLocked()
            return state
        }
    }

    @discardableResult
    public func removeServer(endpoint: ED2KServerEndpoint) throws -> CoreSnapshot {
        try withLock {
            guard let index = state.servers.firstIndex(where: { $0.endpoint == endpoint }) else {
                throw CoreServiceError.serverNotFound(endpoint.address)
            }

            let wasPreferred = state.servers[index].isPreferred
            state.servers.remove(at: index)
            if wasPreferred, state.servers.isEmpty == false {
                state.servers[0].isPreferred = true
            }
            try persistServers()
            recordNetworkUpdateLocked()
            return state
        }
    }

    @discardableResult
    public func importServers(_ endpoints: [ED2KServerEndpoint]) throws -> CoreSnapshot {
        try withLock {
            if try importServersLocked(endpoints) {
                recordNetworkUpdateLocked()
            }
            return state
        }
    }

    @discardableResult
    public func bootstrapBundledServersIfNeeded() throws -> CoreSnapshot {
        guard let transferStore else {
            return snapshot()
        }

        let currentSeedVersion = try transferStore.loadServerBootstrapVersion()
        guard currentSeedVersion < CoreDefaultED2KServers.seedVersion else {
            return snapshot()
        }

        return try withLock {
            var addedCount = 0
            var didChange = false
            var hasPreferredServer = state.servers.contains(where: \.isPreferred)

            for defaultServer in CoreDefaultED2KServers.bundled {
                if let index = state.servers.firstIndex(where: { $0.endpoint == defaultServer.endpoint }) {
                    if state.servers[index].name == state.servers[index].endpoint.address {
                        state.servers[index].name = defaultServer.name
                        didChange = true
                    }
                    if state.servers[index].status == .unavailable {
                        state.servers[index].status = defaultServer.endpoint == activeServerEndpoint ? .connected : .available
                        didChange = true
                    }
                    continue
                }

                state.servers.append(
                    CoreServer(
                        endpoint: defaultServer.endpoint,
                        name: defaultServer.name,
                        status: defaultServer.endpoint == activeServerEndpoint ? .connected : .available,
                        isPreferred: hasPreferredServer == false
                    )
                )
                hasPreferredServer = true
                addedCount += 1
                didChange = true
            }

            if didChange {
                try persistServers()
                recordNetworkUpdateLocked()
            }
            try transferStore.saveServerBootstrapVersion(CoreDefaultED2KServers.seedVersion)

            if addedCount > 0 {
                emitNetworkLog("eD2k bundled server list seeded: \(addedCount) server(s)")
            }

            return state
        }
    }

    @discardableResult
    public func search(query rawQuery: String) -> CoreSnapshot {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        var connection: ED2KServerTCPConnection?
        var autoConnectConfiguration: ED2KServerSessionConfiguration?
        let snapshot = withLock {
            activeSearchQuery = query.isEmpty ? nil : query

            if state.searchResults.isEmpty == false {
                state.searchResults.removeAll()
                recordNetworkUpdateLocked()
            }

            persistResumeCheckpointLocked()

            guard query.isEmpty == false else {
                emitNetworkLog("eD2k search cleared.")
                return state
            }

            connection = serverConnection
            guard connection != nil else {
                autoConnectConfiguration = searchAutoconnectConfigurationLocked()
                if autoConnectConfiguration != nil {
                    emitNetworkLog("eD2k search queued until a server connection becomes ready: \(query)")
                } else {
                    emitNetworkLog("eD2k search could not start because there is no known server to connect: \(query)")
                }
                return state
            }

            guard isServerSessionReady else {
                connection = nil
                emitNetworkLog("eD2k search queued until the server accepts login: \(query)")
                return state
            }

            return state
        }

        guard query.isEmpty == false else {
            return snapshot
        }

        if let autoConnectConfiguration {
            return connectToServer(autoConnectConfiguration)
        }

        guard let connection else {
            return snapshot
        }

        _ = connection.sendSearch(query: query)
        return snapshot
    }

    @discardableResult
    private func updateTransfer(
        id rawID: String,
        mutate: (inout CoreTransfer) -> Void
    ) throws -> CoreSnapshot {
        let id = try parseTransferID(rawID)
        return try withLock {
            guard let index = state.transfers.firstIndex(where: { $0.id == id }) else {
                throw CoreServiceError.transferNotFound(rawID)
            }

            let previous = state.transfers[index]
            mutate(&state.transfers[index])
            if state.transfers[index] != previous {
                try persist(state.transfers[index])
                recordLocked(.transferUpdated, transfer: state.transfers[index])
            }
            return state
        }
    }

    private func parseTransferID(_ rawID: String) throws -> UUID {
        guard let id = UUID(uuidString: rawID) else {
            throw CoreServiceError.invalidTransferID(rawID)
        }
        return id
    }

    private func scheduleReconnect() {
        let config = withLock { reconnectConfiguration }
        guard let config else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.connectToServer(config)
        }
        withLock {
            reconnectWorkItem?.cancel()
            reconnectWorkItem = workItem
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: workItem)
        emitNetworkLog("eD2k reconnect scheduled in 15 s")
    }

    private func applyServerConnectionEvent(
        _ event: ED2KServerTCPConnectionEvent,
        endpoint: ED2KServerEndpoint,
        generation: UInt64
    ) {
        var peerDownloadPlan: PeerDownloadPlan?
        var shouldScheduleReconnect = false
        var pendingSearchAfterLogin: String?
        var pendingSearchConnection: ED2KServerTCPConnection?
        var postLoginConnection: ED2KServerTCPConnection?
        var pendingSourceBootstrapAfterLogin = false
        var failoverEndpoint: ED2KServerEndpoint?
        var shouldFailoverPendingSearch = false

        withLock {
            guard generation == serverConnectionGeneration else {
                return
            }

            switch event {
            case .stateChanged(.connecting):
                updateNetworkLocked(
                    isConnected: false,
                    statusText: "Connecting to \(endpoint.address)",
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k connecting: \(endpoint.address)")
            case .stateChanged(.waiting(let message)):
                updateNetworkLocked(
                    isConnected: false,
                    statusText: "Waiting for connection to \(endpoint.address)",
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k waiting: \(message)")
            case .stateChanged(.connected):
                updateServerStatusesLocked(connectedEndpoint: endpoint)
                updateNetworkLocked(
                    isConnected: true,
                    statusText: "Connected to \(endpoint.address)",
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k connected: \(endpoint.address)")
            case .stateChanged(.disconnected):
                let wasServerSessionReady = isServerSessionReady
                updateServerStatusesLocked(connectedEndpoint: nil)
                updateNetworkLocked(
                    isConnected: false,
                    statusText: "Offline",
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k disconnected: \(endpoint.address)")
                serverConnection = nil
                isServerSessionReady = false
                requeueActiveServerCallbackRequestLocked()
                shouldFailoverPendingSearch = activeSearchQuery?.isEmpty == false && wasServerSessionReady == false
                shouldScheduleReconnect = shouldFailoverPendingSearch == false
                // Clear stale search results on disconnect
                if !state.searchResults.isEmpty {
                    state.searchResults.removeAll()
                    recordNetworkUpdateLocked()
                }
                if !wasServerSessionReady {
                    markServerUnavailableLocked(endpoint)
                }
            case .stateChanged(.failed(let message)):
                let wasServerSessionReady = isServerSessionReady
                updateServerStatusesLocked(connectedEndpoint: nil)
                updateNetworkLocked(
                    isConnected: false,
                    statusText: message,
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k connection failed: \(message)")
                serverConnection = nil
                isServerSessionReady = false
                requeueActiveServerCallbackRequestLocked()
                shouldFailoverPendingSearch = activeSearchQuery?.isEmpty == false && wasServerSessionReady == false
                shouldScheduleReconnect = shouldFailoverPendingSearch == false
                // Auto-failover: try next server immediately
                if shouldScheduleReconnect,
                   let next = nextFailoverEndpointLocked(excluding: endpoint) {
                    failoverEndpoint = next
                    shouldScheduleReconnect = false
                }
            case .loginSent:
                updateServerStatusesLocked(connectedEndpoint: endpoint)
                updateNetworkLocked(
                    isConnected: true,
                    statusText: "Login sent to \(endpoint.address)",
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k login sent: \(endpoint.address)")
            case .searchSent(let query):
                updateNetworkLocked(
                    isConnected: state.network.isConnected,
                    statusText: "Searching: \(query)",
                    highID: state.network.highID,
                    kadNodes: state.network.kadNodes
                )
                emitNetworkLog("eD2k search sent: \(query)")
            case .searchFailed(let query, let message):
                emitNetworkLog("eD2k search failed for \"\(query)\": \(message)")
            case .sourceLookupSent(let hash):
                emitNetworkLog("eD2k source lookup sent: \(hash)")
            case .sourceLookupFailed(let hash, let message):
                emitNetworkLog("eD2k source lookup failed for \(hash): \(message)")
            case .callbackRequestSent(let clientID):
                emitNetworkLog("eD2k server callback request sent for clientID \(clientID)")
            case .callbackRequestFailed(let clientID, let message):
                emitNetworkLog("eD2k server callback request failed for clientID \(clientID): \(message)")
                requeueActiveServerCallbackRequestLocked()
            case .loginFailed(let message):
                let wasServerSessionReady = isServerSessionReady
                updateServerStatusesLocked(connectedEndpoint: nil)
                updateNetworkLocked(
                    isConnected: false,
                    statusText: message,
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k login failed: \(message)")
                serverConnection = nil
                isServerSessionReady = false
                requeueActiveServerCallbackRequestLocked()
                shouldFailoverPendingSearch = activeSearchQuery?.isEmpty == false && wasServerSessionReady == false
                shouldScheduleReconnect = shouldFailoverPendingSearch == false
            case .emptyOfferFilesSent:
                emitNetworkLog("eD2k empty offer-files sent.")
            case .emptyOfferFilesFailed(let message):
                emitNetworkLog("eD2k empty offer-files failed: \(message)")
            case .offerFilesSent:
                emitNetworkLog("eD2k offer-files sent.")
            case .offerFilesFailed(let message):
                emitNetworkLog("eD2k offer-files failed: \(message)")
            case .receiveFailed(let message):
                let wasServerSessionReady = isServerSessionReady
                updateServerStatusesLocked(connectedEndpoint: nil)
                updateNetworkLocked(
                    isConnected: false,
                    statusText: message,
                    highID: false,
                    kadNodes: 0
                )
                emitNetworkLog("eD2k receive failed: \(message)")
                serverConnection = nil
                isServerSessionReady = false
                requeueActiveServerCallbackRequestLocked()
                shouldFailoverPendingSearch = activeSearchQuery?.isEmpty == false && wasServerSessionReady == false
                shouldScheduleReconnect = shouldFailoverPendingSearch == false
            case .sessionEvent(let sessionEvent):
                let outcome = applyServerSessionEventLocked(sessionEvent)
                peerDownloadPlan = outcome.peerDownloadPlan
                failoverEndpoint = outcome.failoverEndpoint
                if outcome.sessionAccepted {
                    postLoginConnection = serverConnection
                    if let query = activeSearchQuery,
                       query.isEmpty == false,
                       let connection = serverConnection {
                        pendingSearchAfterLogin = query
                        pendingSearchConnection = connection
                    }
                    pendingSourceBootstrapAfterLogin = true
                }
            }

            if failoverEndpoint == nil, shouldFailoverPendingSearch {
                failoverEndpoint = nextFailoverEndpointLocked(excluding: endpoint)
                if failoverEndpoint == nil {
                    shouldScheduleReconnect = true
                }
            }
        }

        if let peerDownloadPlan {
            startPeerDownload(using: peerDownloadPlan)
            startPeerDownloadsIfPossible(for: peerDownloadPlan.transferID)
        }
        if pendingSourceBootstrapAfterLogin {
            requestSourcesForActiveTransfersIfPossible()
        }
        if let postLoginConnection {
            if let sharedFiles = sharedFileList {
                let files = sharedFiles.allSharedFiles()
                if files.isEmpty {
                    _ = postLoginConnection.sendEmptyOfferFiles()
                } else {
                    _ = postLoginConnection.sendOfferFiles(fileHashes: files.map(\.ed2kHash))
                }
            } else {
                _ = postLoginConnection.sendEmptyOfferFiles()
            }
        }
        requestServerCallbacksIfPossible()
        if let failoverEndpoint {
            failoverToServer(failoverEndpoint)
            return
        }
        if let query = pendingSearchAfterLogin, let connection = pendingSearchConnection {
            _ = connection.sendSearch(query: query)
        }
        if shouldScheduleReconnect {
            scheduleReconnect()
        }
    }

    private func applyServerSessionEventLocked(
        _ event: ED2KServerSessionEvent
    ) -> (peerDownloadPlan: PeerDownloadPlan?, failoverEndpoint: ED2KServerEndpoint?, sessionAccepted: Bool) {
        switch event {
        case .outgoingLogin:
            return (nil, nil, false)
        case .idChange(let idChange):
            isServerSessionReady = true
            if var configuration = reconnectConfiguration {
                configuration.clientID = idChange.clientID
                reconnectConfiguration = configuration
            }
            let statusText = idChange.highID
                ? "Connected to \(activeServerEndpoint?.address ?? "eD2k server") (HighID)"
                : "Connected to \(activeServerEndpoint?.address ?? "eD2k server")"
            updateNetworkLocked(
                isConnected: true,
                statusText: statusText,
                highID: idChange.highID,
                kadNodes: state.network.kadNodes
            )
            emitNetworkLog(
                "eD2k login accepted: clientID \(idChange.clientID) (\(idChange.highID ? "HighID" : "LowID"))"
            )
            return (nil, nil, true)
        case .serverMessage(let message):
            let firstLine = message.lines.first ?? message.rawText
            let inferredHighID = inferHighIDFromServerMessage(firstLine)
            updateNetworkLocked(
                isConnected: true,
                statusText: statusTextForServerMessageLocked(firstLine, inferredHighID: inferredHighID),
                highID: inferredHighID ?? state.network.highID,
                kadNodes: state.network.kadNodes
            )
            emitNetworkLog("eD2k server message: \(message.rawText)")
            // Don't failover after login has been accepted — server MOTD
            // warnings like "too old" are informational, not rejections.
            let failover: ED2KServerEndpoint?
            if isServerSessionReady {
                failover = nil
            } else {
                failover = failoverEndpointForServerMessageLocked(
                    firstLine,
                    activeEndpoint: activeServerEndpoint
                )
            }
            return (
                nil,
                failover,
                false
            )
        case .serverStatus(let serverStatus):
            if let activeServerEndpoint,
               let index = state.servers.firstIndex(where: { $0.endpoint == activeServerEndpoint }) {
                state.servers[index].users = Int(serverStatus.users)
                state.servers[index].files = Int(serverStatus.files)
                state.servers[index].status = .connected
                recordNetworkUpdateLocked()
            }
            emitNetworkLog("eD2k server status: \(serverStatus.users) user(s), \(serverStatus.files) file(s)")
            return (nil, nil, false)
        case .serverIdentity(let identity):
            let wasServerSessionReady = isServerSessionReady
            isServerSessionReady = true
            _ = try? importServersLocked([identity.endpoint])
            updateServerStatusesLocked(connectedEndpoint: identity.endpoint)
            updateNetworkLocked(
                isConnected: true,
                statusText: "Server \(identity.endpoint.address)",
                highID: state.network.highID,
                kadNodes: state.network.kadNodes
            )
            emitNetworkLog("eD2k server identified: \(identity.endpoint.address)")
            return (nil, nil, wasServerSessionReady == false)
        case .serverList(let servers):
            do {
                if try importServersLocked(servers) {
                    recordNetworkUpdateLocked()
                }
            } catch {
                emitNetworkLog("eD2k server list persistence failed: \(error.localizedDescription)")
            }
            emitNetworkLog("eD2k server list received: \(servers.count) entrie(s)")
            return (nil, nil, false)
        case .searchResults(let results):
            mergeSearchResultsLocked(results)
            let searchLabel = activeSearchQuery.map { " para \($0)" } ?? ""
            updateNetworkLocked(
                isConnected: state.network.isConnected,
                statusText: "\(state.searchResults.count) result(s)\(searchLabel)",
                highID: state.network.highID,
                kadNodes: state.network.kadNodes
            )
            emitNetworkLog("eD2k search results received: \(results.count) entrie(s)")
            return (nil, nil, false)
        case .foundSources(let foundSources):
            let peerDownloadPlan = applyFoundSourcesLocked(foundSources)
            emitNetworkLog("eD2k found sources received: \(foundSources.sources.count) entrie(s)")
            return (peerDownloadPlan, nil, false)
        case .callbackRequested(let endpoint):
            let peerDownloadPlan = applyServerCallbackRequestedLocked(endpoint)
            emitNetworkLog("eD2k server callback requested: \(endpoint.address)")
            return (peerDownloadPlan, nil, false)
        case .callbackFailed:
            requeueActiveServerCallbackRequestLocked()
            emitNetworkLog("eD2k server callback failed.")
            return (nil, nil, false)
        case .unhandledPacket(let packet):
            emitNetworkLog(
                "eD2k unhandled packet: opcode 0x\(String(format: "%02X", packet.opcode))"
            )
            return (nil, nil, false)
        }
    }

    private func failoverEndpointForServerMessageLocked(
        _ serverMessage: String,
        activeEndpoint: ED2KServerEndpoint?
    ) -> ED2KServerEndpoint? {
        guard shouldFailoverForServerMessage(serverMessage),
              let activeEndpoint else {
            return nil
        }

        if let index = state.servers.firstIndex(where: { $0.endpoint == activeEndpoint }),
           state.servers[index].status != .unavailable {
            state.servers[index].status = .unavailable
            do {
                try persistServers()
                recordNetworkUpdateLocked()
            } catch {
                emitNetworkLog("eD2k failover status persistence failed: \(error.localizedDescription)")
            }
        }

        guard let nextEndpoint = nextFailoverEndpointLocked(excluding: activeEndpoint) else {
            emitNetworkLog("eD2k server rejected login as too old, but no alternate server is available.")
            return nil
        }

        emitNetworkLog(
            "eD2k server rejected login as too old; switching to \(nextEndpoint.address)."
        )
        return nextEndpoint
    }

    private func shouldFailoverForServerMessage(_ serverMessage: String) -> Bool {
        let normalized = serverMessage.lowercased()
        return normalized.contains("too old")
            && (normalized.contains("edonkey") || normalized.contains("client") || normalized.contains("id"))
    }

    private func inferHighIDFromServerMessage(_ serverMessage: String) -> Bool? {
        let normalized = serverMessage.lowercased()
        if normalized.contains("highid") || normalized.contains("high id") {
            return true
        }
        if normalized.contains("lowid") || normalized.contains("low id") {
            return false
        }
        return nil
    }

    private func statusTextForServerMessageLocked(
        _ serverMessage: String,
        inferredHighID: Bool?
    ) -> String {
        guard let inferredHighID else {
            return serverMessage
        }

        let serverLabel = activeServerEndpoint?.address ?? "eD2k server"
        if inferredHighID {
            return "Connected with HighID to \(serverLabel)"
        }

        if isPeerListenerReady {
            return "Connected with LowID to \(serverLabel). TCP listener :\(state.network.tcpPort) is active, but the external network still cannot reach it."
        }

        return "Connected with LowID to \(serverLabel). Could not open TCP listener :\(state.network.tcpPort)."
    }

    private func nextFailoverEndpointLocked(excluding endpoint: ED2KServerEndpoint) -> ED2KServerEndpoint? {
        guard state.servers.isEmpty == false else {
            return nil
        }

        let orderedServers: [CoreServer]
        if let currentIndex = state.servers.firstIndex(where: { $0.endpoint == endpoint }) {
            let tail = state.servers.index(after: currentIndex)..<state.servers.endIndex
            let head = state.servers.startIndex..<currentIndex
            orderedServers = Array(state.servers[tail]) + Array(state.servers[head])
        } else {
            orderedServers = state.servers
        }

        if let available = orderedServers.first(where: {
            $0.endpoint != endpoint && $0.status != .unavailable
        }) {
            return available.endpoint
        }

        return orderedServers.first(where: { $0.endpoint != endpoint })?.endpoint
    }

    private func failoverToServer(_ endpoint: ED2KServerEndpoint) {
        let configuration = withLock { makeServerConfigurationLocked(for: endpoint) }

        _ = connectToServer(configuration)
    }

    private func searchAutoconnectConfigurationLocked() -> ED2KServerSessionConfiguration? {
        if let reconnectConfiguration,
           isServerUnavailableLocked(reconnectConfiguration.endpoint) == false {
            return reconnectConfiguration
        }
        guard let endpoint = preferredAvailableServerEndpointLocked() else {
            return nil
        }
        return makeServerConfigurationLocked(for: endpoint)
    }

    private func preferredAvailableServerEndpointLocked() -> ED2KServerEndpoint? {
        state.servers.first { $0.isPreferred && $0.status != .unavailable }?.endpoint
            ?? state.servers.first { $0.status != .unavailable }?.endpoint
            ?? state.servers.first(where: \.isPreferred)?.endpoint
            ?? state.servers.first?.endpoint
    }

    private func isServerUnavailableLocked(_ endpoint: ED2KServerEndpoint) -> Bool {
        state.servers.first { $0.endpoint == endpoint }?.status == .unavailable
    }

    private func makeServerConfigurationLocked(
        for endpoint: ED2KServerEndpoint
    ) -> ED2KServerSessionConfiguration {
        ED2KServerSessionConfiguration(
            endpoint: endpoint,
            userHash: clientUserHash,
            clientID: reconnectConfiguration?.clientID ?? 0,
            tcpPort: reconnectConfiguration?.tcpPort ?? UInt16(state.network.tcpPort),
            nickname: reconnectConfiguration?.nickname ?? "MacMule",
            protocolVersion: reconnectConfiguration?.protocolVersion ?? ED2KLoginRequest.defaultProtocolVersion,
            flags: reconnectConfiguration?.flags ?? ED2KLoginRequest.defaultCompressionFlags
        )
    }

    private func makePeerListenerConfiguration(
        for configuration: ED2KServerSessionConfiguration
    ) -> ED2KPeerSessionConfiguration {
        ED2KPeerSessionConfiguration(
            userHash: configuration.userHash,
            clientID: configuration.clientID,
            tcpPort: configuration.tcpPort,
            nickname: configuration.nickname,
            serverEndpoint: configuration.endpoint
        )
    }

    private func makeCurrentPeerSessionConfigurationLocked() -> ED2KPeerSessionConfiguration {
        ED2KPeerSessionConfiguration(
            userHash: clientUserHash,
            clientID: reconnectConfiguration?.clientID ?? 0,
            tcpPort: reconnectConfiguration?.tcpPort ?? UInt16(state.network.tcpPort),
            nickname: reconnectConfiguration?.nickname ?? "MacMule",
            serverEndpoint: activeServerEndpoint
                ?? reconnectConfiguration?.endpoint
                ?? ED2KServerEndpoint(host: "0.0.0.0", port: 0)
        )
    }

    private func applyPeerListenerEvent(_ event: ED2KPeerTCPListenerEvent) {
        var connectionToStart: ED2KServerTCPConnection?
        var portMappingRequest: (tcpPort: UInt16, udpPort: UInt16)?

        withLock {
            switch event {
            case .stateChanged(.starting(let port)):
                updateNetworkPortsLocked(tcpPort: Int(port))
                emitNetworkLog("eD2k peer listener starting on :\(port)")
            case .stateChanged(.listening(let port)):
                isPeerListenerReady = true
                peerListenerStartupTimeoutWorkItem?.cancel()
                peerListenerStartupTimeoutWorkItem = nil
                updateNetworkPortsLocked(tcpPort: Int(port))
                emitNetworkLog("eD2k peer listener ready on :\(port)")
                portMappingRequest = (tcpPort: port, udpPort: UInt16(state.network.udpPort))
                if let pendingServerConnectionStart, pendingServerConnectionStart === serverConnection {
                    connectionToStart = pendingServerConnectionStart
                    self.pendingServerConnectionStart = nil
                }
            case .stateChanged(.failed(let message)):
                isPeerListenerReady = false
                peerListenerStartupTimeoutWorkItem?.cancel()
                peerListenerStartupTimeoutWorkItem = nil
                if state.network.isConnected {
                    updateNetworkLocked(
                        isConnected: true,
                        statusText: "Connected, but peer TCP listener failed: \(message)",
                        highID: state.network.highID,
                        kadNodes: state.network.kadNodes
                    )
                }
                emitNetworkLog("eD2k peer listener failed: \(message)")
                if let pendingServerConnectionStart, pendingServerConnectionStart === serverConnection {
                    connectionToStart = pendingServerConnectionStart
                    self.pendingServerConnectionStart = nil
                }
            case .stateChanged(.cancelled):
                isPeerListenerReady = false
                emitNetworkLog("eD2k peer listener cancelled")
            case .accepted(let endpoint):
                emitNetworkLog("eD2k incoming peer accepted: \(endpoint.address)")
            case .sessionEvent(let endpoint, let sessionEvent):
                applyIncomingPeerSessionEventLocked(sessionEvent, endpoint: endpoint)
            case .helloAnswerSent(let endpoint):
                emitNetworkLog("eD2k incoming peer helloanswer sent: \(endpoint.address)")
            case .helloAnswerFailed(let endpoint, let message):
                emitNetworkLog("eD2k incoming peer helloanswer failed for \(endpoint.address): \(message)")
            case .receiveFailed(let endpoint, let message):
                emitNetworkLog("eD2k incoming peer receive failed for \(endpoint.address): \(message)")
            }
        }

        if let portMappingRequest {
            ensurePeerPortMapping(tcpPort: portMappingRequest.tcpPort, udpPort: portMappingRequest.udpPort)
        }
        connectionToStart?.start()
    }

    private func ensurePeerPortMapping(tcpPort: UInt16, udpPort: UInt16) {
        guard let peerPortMapper else { return }

        emitNetworkLog("Automatic mapping trying to open TCP :\(tcpPort) and UDP :\(udpPort).")
        peerPortMapper.ensureMappings(tcpPort: tcpPort, udpPort: udpPort) { [weak self] result in
            guard let self else { return }
            let summary: String
            if result.tcpMapped && result.udpMapped {
                summary = "Automatic mapping opened TCP :\(tcpPort) and UDP :\(udpPort). \(result.detail)"
            } else if result.tcpMapped || result.udpMapped {
                summary = "Automatic mapping opened ports partially (TCP=\(result.tcpMapped), UDP=\(result.udpMapped)). \(result.detail)"
            } else {
                summary = "Automatic mapping could not open the ports. \(result.detail)"
            }
            self.emitNetworkLog(summary)
        }
    }

    private func schedulePeerListenerStartupTimeout(
        for connection: ED2KServerTCPConnection,
        endpoint: ED2KServerEndpoint
    ) {
        let workItem = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection else { return }
            let shouldStart = self.withLock { () -> Bool in
                guard let pendingServerConnectionStart,
                      pendingServerConnectionStart === connection,
                      self.serverConnection === connection else {
                    return false
                }

                self.pendingServerConnectionStart = nil
                self.peerListenerStartupTimeoutWorkItem = nil
                return true
            }

            guard shouldStart else { return }
            self.emitNetworkLog(
                "eD2k peer listener startup timed out on :\(connection.configuration.tcpPort); continuing server login to \(endpoint.address)"
            )
            connection.start()
        }

        withLock {
            peerListenerStartupTimeoutWorkItem?.cancel()
            peerListenerStartupTimeoutWorkItem = workItem
        }

        DispatchQueue.global().asyncAfter(
            deadline: .now() + Self.peerListenerStartupTimeout,
            execute: workItem
        )
    }

    private func applyIncomingPeerSessionEventLocked(
        _ event: ED2KPeerSessionEvent,
        endpoint: ED2KPeerEndpoint
    ) {
        // TODO: Upload serving — needs connection reference from peer listener to send blocks back
        // This requires architectural work: pass the ED2KPeerTCPConnection to the event handler
        switch event {
        case .outgoingHello, .outgoingHelloAnswer, .outgoingFileRequest, .outgoingSetRequestFileID, .outgoingStartUploadRequest, .outgoingSourceExchangeRequest:
            break
        case .peerHello(let hello):
            emitNetworkLog("eD2k incoming peer hello received from \(endpoint.address) on port \(hello.tcpPort)")
        case .peerHelloAnswer(let hello):
            emitNetworkLog("eD2k incoming peer helloanswer received from \(endpoint.address) on port \(hello.tcpPort)")
        case .partHashSet(let hashSet):
            emitNetworkLog("eD2k incoming peer hashset received unexpectedly: \(hashSet.partHashes.count) part(es) from \(endpoint.address)")
        case .sourceExchangeAnswer(let answer):
            emitNetworkLog("eD2k incoming peer source-exchange received unexpectedly: \(answer.sources.count) source(s) from \(endpoint.address)")
        case .partRequest(let request):
            emitNetworkLog("eD2k peer upload request: \(request.ranges.count) range(s) from \(endpoint.address)")
            sharedFileList?.recordRequest(fileHash: request.fileHash, bytes: 0)
            uploadQueue?.addClientToWaiting(
                clientID: KadUInt128(),
                clientIP: endpoint.address,
                clientPort: endpoint.port,
                fileName: "upload",
                fileHash: request.fileHash
            )
            // TODO: actual block serving requires connection reference
        case .sendingPart(let sendingPart):
            emitNetworkLog("eD2k incoming peer sent unexpected block of \(sendingPart.block.count) byte(s) from \(endpoint.address)")
        case .fileRequestAnswerNoFile:
            emitNetworkLog("eD2k incoming peer reported missing file from \(endpoint.address)")
        case .acceptUploadRequest:
            emitNetworkLog("eD2k incoming peer accept-upload ignored from \(endpoint.address)")
        case .queueRank(let rank):
            emitNetworkLog("eD2k incoming peer queue rank \(rank) ignored from \(endpoint.address)")
        case .unhandledPacket(let packet):
            emitNetworkLog("eD2k incoming peer unhandled packet: opcode 0x\(String(format: "%02X", packet.opcode))")
        }
    }

    private func updateNetworkLocked(
        isConnected: Bool,
        statusText: String,
        highID: Bool,
        kadNodes: Int
    ) {
        let previous = state.network
        state.network.isConnected = isConnected
        state.network.statusText = statusText
        state.network.highID = highID
        state.network.kadNodes = kadNodes

        guard state.network != previous else {
            return
        }

        recordNetworkUpdateLocked()
    }

    private func updateNetworkPortsLocked(tcpPort: Int? = nil, udpPort: Int? = nil) {
        let previous = state.network
        if let tcpPort {
            state.network.tcpPort = tcpPort
        }
        if let udpPort {
            state.network.udpPort = udpPort
        }

        guard state.network != previous else {
            return
        }

        recordNetworkUpdateLocked()
    }

    private func recordNetworkUpdateLocked() {
        events.append(
            CoreEvent(
                sequence: nextEventSequence,
                kind: .networkUpdated
            )
        )
        nextEventSequence += 1
        persistResumeCheckpointLocked()
    }

    private func recordKadUpdateLocked() {
        events.append(
            CoreEvent(
                sequence: nextEventSequence,
                kind: .kadUpdated
            )
        )
        nextEventSequence += 1
    }

    private func recordKadSearchResultLocked() {
        events.append(
            CoreEvent(
                sequence: nextEventSequence,
                kind: .kadSearchResult
            )
        )
        nextEventSequence += 1
    }

    private func recordLocked(_ kind: CoreEventKind, transfer: CoreTransfer) {
        events.append(
            CoreEvent(
                sequence: nextEventSequence,
                kind: kind,
                transferID: transfer.id,
                transfer: transfer
            )
        )
        nextEventSequence += 1
        persistResumeCheckpointLocked()
    }

    private func emitNetworkLog(_ message: String) {
        networkLogHandler?("[network] \(message)")
    }

    private func mergeSearchResultsLocked(_ incomingResults: [ED2KSearchResult]) {
        guard incomingResults.isEmpty == false else {
            return
        }

        emitNetworkLog("eD2k search received \(incomingResults.count) result(s)")

        // Filter out results with server error messages as filenames
        let cleanResults = incomingResults.filter { result in
            let fileName = result.stringTag(named: ED2KSearchTagName.fileName)
                ?? result.fileHash.hexadecimalString
            let lower = fileName.lowercased()
            return !lower.contains("too old") && !lower.contains("upgrade")
        }

        if cleanResults.count < incomingResults.count {
            emitNetworkLog("eD2k search filtered \(incomingResults.count - cleanResults.count) result(s)")
        }

        guard cleanResults.isEmpty == false else {
            emitNetworkLog("eD2k search returned 0 valid results (filtered)")
            return
        }

        emitNetworkLog("eD2k search merging \(cleanResults.count) result(s)")
        var merged = state.searchResults
        var knownHashes = Set(merged.map(\.ed2kHash))
        var didChange = false

        for result in cleanResults {
            let mappedResult = CoreSearchResult(
                ed2kSearchResult: result,
                network: activeServerEndpoint?.address ?? "eD2k"
            )

            if knownHashes.insert(mappedResult.ed2kHash).inserted {
                merged.append(mappedResult)
                didChange = true
            }
        }

        guard didChange else {
            return
        }

        state.searchResults = merged.sorted { lhs, rhs in
            if lhs.sources == rhs.sources {
                return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
            return lhs.sources > rhs.sources
        }
        recordNetworkUpdateLocked()
    }

    private func applyInitialSourcesLocked(_ sources: [ED2KFoundSource], fileHash: Data, transferID: UUID) {
        guard sources.isEmpty == false,
              let index = state.transfers.firstIndex(where: { $0.id == transferID }) else {
            return
        }

        let directSourceCount = rememberPeerSourcesLocked(sources, fileHash: fileHash, for: transferID)
        state.transfers[index].sources = max(state.transfers[index].sources, sources.count)
        state.transfers[index].availability = max(state.transfers[index].availability, directSourceCount)
    }

    private func applyFoundSourcesLocked(_ foundSources: ED2KFoundSources) -> PeerDownloadPlan? {
        let fileHash = foundSources.fileHash.hexadecimalString
        guard let index = state.transfers.firstIndex(where: { $0.ed2kHash == fileHash }) else {
            return nil
        }

        let previous = state.transfers[index]
        let directSourceCount = rememberPeerSourcesLocked(
            foundSources.sources,
            fileHash: foundSources.fileHash,
            for: state.transfers[index].id
        )
        state.transfers[index].sources = foundSources.sources.count
        state.transfers[index].availability = directSourceCount
        if state.transfers[index].status == .downloading, directSourceCount == 0 {
            state.transfers[index].status = .queued
            state.transfers[index].downloadSpeedBytesPerSecond = 0
            removeDownloadSpeedStateLocked(for: state.transfers[index].id)
        }

        let transfer = state.transfers[index]

        if transfer != previous {
            try? persist(transfer)
            recordLocked(.transferUpdated, transfer: transfer)
        }

        return makePeerDownloadPlanLocked(transfer: transfer)
    }

    private func requestSourcesIfPossible(for transfer: CoreTransfer, force: Bool = false) {
        let shouldFlush = withLock {
            let currentTransfer = state.transfers.first(where: { $0.id == transfer.id }) ?? transfer
            guard Self.isSourceLookupEligible(currentTransfer),
                  force || shouldRequestSourcesLocked(for: currentTransfer) else {
                return false
            }

            enqueueSourceLookupLocked(for: currentTransfer.id)
            return isServerSessionReady && serverConnection != nil
        }

        if shouldFlush {
            flushQueuedSourceLookupsIfPossible()
        } else {
            scheduleSourceLookupMaintenanceIfNeeded()
        }
    }

    func refreshSourcesForActiveTransfers() {
        performSourceLookupMaintenance()
    }

    private func flushQueuedSourceLookupsIfPossible() {
        let requests = withLock { () -> [SourceLookupSendRequest] in
            guard isServerSessionReady, let connection = serverConnection else {
                return []
            }

            var selectedRequests: [SourceLookupSendRequest] = []
            var remainingTransferIDs: [UUID] = []
            let now = Date()

            for transferID in pendingSourceLookupTransferIDs {
                guard selectedRequests.count < Self.maxSourceLookupRequestsPerPass else {
                    remainingTransferIDs.append(transferID)
                    continue
                }

                guard let transfer = state.transfers.first(where: { $0.id == transferID }),
                      Self.isSourceLookupEligible(transfer) else {
                    continue
                }

                guard let fileHash = Data(hexadecimalString: transfer.ed2kHash) else {
                    emitNetworkLog("eD2k source lookup skipped for invalid hash: \(transfer.ed2kHash)")
                    continue
                }

                sourceLookupLastRequestedAt[transferID] = now
                selectedRequests.append(
                    SourceLookupSendRequest(
                        transferID: transferID,
                        fileHash: fileHash,
                        fileSizeInBytes: transfer.sizeInBytes,
                        connection: connection
                    )
                )
            }

            pendingSourceLookupTransferIDs = remainingTransferIDs
            if selectedRequests.isEmpty == false {
                emitNetworkLog("eD2k source lookup queue processing: \(selectedRequests.count) transfer(s)")
            }
            return selectedRequests
        }

        var failedTransferIDs: [UUID] = []
        for request in requests {
            if request.connection.sendSourceLookup(
                fileHash: request.fileHash,
                fileSizeInBytes: request.fileSizeInBytes
            ) == false {
                failedTransferIDs.append(request.transferID)
            }
        }

        if failedTransferIDs.isEmpty == false {
            withLock {
                for transferID in failedTransferIDs {
                    sourceLookupLastRequestedAt.removeValue(forKey: transferID)
                    enqueueSourceLookupLocked(for: transferID)
                }
            }
        }

        scheduleSourceLookupMaintenanceIfNeeded()
    }

    private func performSourceLookupMaintenance() {
        let activeTransferIDs = withLock { () -> [UUID] in
            sourceLookupMaintenanceWorkItem = nil
            let now = Date()
            var activeTransferIDs: [UUID] = []

            for transfer in state.transfers where Self.isSourceLookupEligible(transfer) {
                activeTransferIDs.append(transfer.id)
                if shouldRequestSourcesLocked(for: transfer, now: now) {
                    enqueueSourceLookupLocked(for: transfer.id)
                }
            }

            return activeTransferIDs
        }

        flushQueuedSourceLookupsIfPossible()

        for transferID in activeTransferIDs {
            startPeerDownloadsIfPossible(for: transferID)
        }
        scheduleSourceLookupMaintenanceIfNeeded()
    }

    private func scheduleSourceLookupMaintenanceIfNeeded() {
        let workItem = withLock { () -> DispatchWorkItem? in
            guard sourceLookupMaintenanceWorkItem == nil,
                  isServerSessionReady,
                  state.transfers.contains(where: Self.isSourceLookupEligible) else {
                return nil
            }

            let item = DispatchWorkItem { [weak self] in
                self?.performSourceLookupMaintenance()
            }
            sourceLookupMaintenanceWorkItem = item
            return item
        }

        guard let workItem else {
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.sourceLookupMaintenanceInterval,
            execute: workItem
        )
    }

    private func enqueueSourceLookupLocked(for transferID: UUID) {
        if pendingSourceLookupTransferIDs.contains(transferID) == false {
            pendingSourceLookupTransferIDs.append(transferID)
        }
    }

    private func removeSourceLookupStateLocked(for transferID: UUID?) {
        guard let transferID else {
            return
        }
        pendingSourceLookupTransferIDs.removeAll { $0 == transferID }
        sourceLookupLastRequestedAt.removeValue(forKey: transferID)
    }

    private func shouldRequestSourcesLocked(for transfer: CoreTransfer, now: Date = Date()) -> Bool {
        guard let lastRequestedAt = sourceLookupLastRequestedAt[transfer.id] else {
            return true
        }

        let retryInterval = sourceLookupRetryIntervalLocked(for: transfer)
        return now.timeIntervalSince(lastRequestedAt) >= retryInterval
    }

    private func sourceLookupRetryIntervalLocked(for transfer: CoreTransfer) -> TimeInterval {
        let directEndpointCount = peerSourceQueues[transfer.id]?.count ?? 0
        if transfer.sources == 0 || directEndpointCount == 0 {
            return Self.emptySourceLookupRetryInterval
        }
        return Self.normalSourceLookupRetryInterval
    }

    private static func isSourceLookupEligible(_ transfer: CoreTransfer) -> Bool {
        transfer.status == .queued || transfer.status == .downloading
    }

    private func requestServerCallbacksIfPossible() {
        typealias CallbackRequest = (connection: ED2KServerTCPConnection, request: ServerCallbackRequest)
        guard let pending: CallbackRequest = withLock({
            guard isServerSessionReady,
                  let connection = serverConnection,
                  activeServerCallbackRequest == nil,
                  pendingServerCallbackRequests.isEmpty == false else {
                return nil
            }

            let currentServerEndpoint = activeServerEndpoint
            guard let requestIndex = pendingServerCallbackRequests.firstIndex(where: {
                $0.serverEndpoint == nil || $0.serverEndpoint == currentServerEndpoint
            }) else {
                return nil
            }
            let request = pendingServerCallbackRequests.remove(at: requestIndex)
            activeServerCallbackRequest = request
            return (connection, request)
        }) else {
            return
        }

        if pending.connection.sendCallbackRequest(clientID: pending.request.sourceClientID) == false {
            withLock {
                requeueActiveServerCallbackRequestLocked()
            }
        }
    }

    private func requestSourcesForActiveTransfersIfPossible() {
        let transferIDs = withLock { () -> [UUID] in
            let transfers = state.transfers.filter(Self.isSourceLookupEligible)
            for transfer in transfers {
                enqueueSourceLookupLocked(for: transfer.id)
            }
            return transfers.map(\.id)
        }

        guard transferIDs.isEmpty == false else {
            return
        }

        emitNetworkLog("eD2k reactivando \(transferIDs.count) transferencia(s) tras login")
        flushQueuedSourceLookupsIfPossible()
        for transferID in transferIDs {
            startPeerDownloadsIfPossible(for: transferID)
        }
        requestServerCallbacksIfPossible()
    }

    private func startPeerDownload(using plan: PeerDownloadPlan) {
        if ipFilter?.isBlocked(ip: plan.endpoint.host) == true {
            emitNetworkLog("eD2k peer connect blocked by IP filter: \(plan.endpoint.address)")
            return
        }

        let connection = withLock {
            if let existing = peerConnections[plan.transferID]?[plan.endpoint] {
                return existing
            }

            let transport = peerTransportFactory?(plan.endpoint)
                ?? NetworkED2KPeerTCPTransport(endpoint: plan.endpoint)
            let peerConfiguration = makeCurrentPeerSessionConfigurationLocked()
            let connection = ED2KPeerTCPConnection(
                endpoint: plan.endpoint,
                configuration: peerConfiguration,
                transport: transport
            ) { [weak self] event in
                self?.applyPeerConnectionEvent(
                    event,
                    transferID: plan.transferID,
                    fileHash: plan.fileHash,
                    initialRange: plan.range,
                    endpoint: plan.endpoint
                )
            }
            var transferConnections = peerConnections[plan.transferID] ?? [:]
            transferConnections[plan.endpoint] = connection
            peerConnections[plan.transferID] = transferConnections
            emitNetworkLog("eD2k peer connect requested: \(plan.endpoint.address) for transfer \(plan.transferID.uuidString)")
            return connection
        }

        connection.start()
    }

    private func startPeerDownloadsIfPossible(for transferID: UUID) {
        while true {
            let plan: PeerDownloadPlan? = withLock {
                guard let transfer = state.transfers.first(where: { $0.id == transferID }),
                      transfer.status == .queued || transfer.status == .downloading,
                      transfer.completedBytes < transfer.sizeInBytes else {
                    return nil
                }

                return makePeerDownloadPlanLocked(transfer: transfer)
            }
            guard let plan else {
                return
            }
            startPeerDownload(using: plan)
        }
    }

    private func applyPeerConnectionEvent(
        _ event: ED2KPeerTCPConnectionEvent,
        transferID: UUID,
        fileHash: Data,
        initialRange: ED2KPartRange,
        endpoint: ED2KPeerEndpoint
    ) {
        switch event {
        case .stateChanged(.connecting):
            emitNetworkLog("eD2k peer connecting: \(endpoint.address)")
        case .stateChanged(.connected):
            emitNetworkLog("eD2k peer connected: \(endpoint.address)")
        case .stateChanged(.disconnected):
            emitNetworkLog("eD2k peer disconnected: \(endpoint.address)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .stateChanged(.failed(let message)):
            emitNetworkLog("eD2k peer connection failed: \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .helloSent:
            emitNetworkLog("eD2k peer hello sent: \(endpoint.address)")
        case .helloFailed(let message):
            emitNetworkLog("eD2k peer hello failed: \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .fileRequestSent(let hash):
            emitNetworkLog("eD2k peer filename request sent: \(hash)")
        case .fileRequestFailed(let hash, let message):
            emitNetworkLog("eD2k peer filename request failed for \(hash): \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .setRequestFileIDSent(let hash):
            emitNetworkLog("eD2k peer request-file-id sent: \(hash)")
        case .setRequestFileIDFailed(let hash, let message):
            emitNetworkLog("eD2k peer request-file-id failed for \(hash): \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .startUploadRequestSent(let hash):
            emitNetworkLog("eD2k peer queue request sent: \(hash)")
        case .startUploadRequestFailed(let hash, let message):
            emitNetworkLog("eD2k peer queue request failed for \(hash): \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .sourceExchangeRequestSent(let hash):
            emitNetworkLog("eD2k peer source-exchange request sent: \(hash)")
        case .sourceExchangeRequestFailed(let hash, let message):
            emitNetworkLog("eD2k peer source-exchange request failed for \(hash): \(message)")
        case .partHashSetRequestSent(let hash):
            emitNetworkLog("eD2k peer hashset request sent: \(hash)")
        case .partHashSetRequestFailed(let hash, let message):
            emitNetworkLog("eD2k peer hashset request failed for \(hash): \(message)")
            handlePartHashSetRequestFailure(for: transferID, endpoint: endpoint)
        case .partRequestSent(let hash):
            emitNetworkLog("eD2k peer part request sent: \(hash)")
        case .partRequestFailed(let hash, let message):
            emitNetworkLog("eD2k peer part request failed for \(hash): \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .receiveFailed(let message):
            emitNetworkLog("eD2k peer receive failed: \(message)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .sessionEvent(let sessionEvent):
            applyPeerSessionEvent(
                sessionEvent,
                transferID: transferID,
                fileHash: fileHash,
                endpoint: endpoint
            )
        }
    }

    private func applyPeerSessionEvent(
        _ event: ED2KPeerSessionEvent,
        transferID: UUID,
        fileHash: Data,
        endpoint: ED2KPeerEndpoint
    ) {
        switch event {
        case .outgoingHello, .outgoingHelloAnswer, .outgoingFileRequest, .outgoingSetRequestFileID, .outgoingStartUploadRequest, .outgoingSourceExchangeRequest:
            break
        case .peerHello(let hello):
            emitNetworkLog("eD2k peer hello received from \(endpoint.address) on port \(hello.tcpPort)")
        case .peerHelloAnswer(let hello):
            emitNetworkLog("eD2k peer helloanswer received from \(endpoint.address) on port \(hello.tcpPort)")
            sendPeerDownloadNegotiation(transferID: transferID, fileHash: fileHash, endpoint: endpoint)
        case .partHashSet(let hashSet):
            emitNetworkLog("eD2k peer hashset received: \(hashSet.partHashes.count) part(es) desde \(endpoint.address)")
            applyPeerPartHashSet(hashSet, transferID: transferID, endpoint: endpoint)
        case .sourceExchangeAnswer(let answer):
            emitNetworkLog("eD2k peer source-exchange received: \(answer.sources.count) fuente(s) desde \(endpoint.address)")
            applyPeerSourceExchangeAnswer(answer, transferID: transferID, endpoint: endpoint)
        case .partRequest:
            emitNetworkLog("eD2k peer requested upload parts: \(endpoint.address)")
        case .sendingPart(let sendingPart):
            emitNetworkLog(
                "eD2k peer block received: \(sendingPart.block.count) byte(s) at \(sendingPart.startOffset) from \(endpoint.address)"
            )
            clearPeerInflightRange(for: transferID, endpoint: endpoint)
            withLock {
                clearPeerChunkRetryStateLocked(
                    for: transferID,
                    overlapping: ED2KPartRange(
                        startOffset: sendingPart.startOffset,
                        endOffset: sendingPart.endOffset
                    )
                )
                let hadFailures = peerSourceFailures[transferID]?[endpoint, default: 0] != 0
                let hadCooldown = peerSourceCooldowns[transferID]?[endpoint] != nil
                if hadFailures || hadCooldown {
                    var failures = peerSourceFailures[transferID] ?? [:]
                    failures[endpoint] = 0
                    peerSourceFailures[transferID] = failures
                    var cooldowns = peerSourceCooldowns[transferID] ?? [:]
                    cooldowns.removeValue(forKey: endpoint)
                    peerSourceCooldowns[transferID] = cooldowns
                    reorderPeerSourceQueueLocked(for: transferID)
                    persistPeerSourceStateLocked(for: transferID)
                }
            }
            do {
                let snapshot = try writeBlock(
                    id: transferID.uuidString,
                    offset: UInt64(sendingPart.startOffset),
                    data: sendingPart.block,
                    sourceEndpoint: endpoint
                )
                rarityScheduler?.updateAvailability(
                    fileHash: fileHash,
                    partIndex: Int(sendingPart.startOffset / CoreChunkMap.ed2kChunkSize),
                    count: 1
                )
                if let transfer = snapshot.transfers.first(where: { $0.id == transferID }),
                   transfer.status == .completed || transfer.status == .failed {
                    cancelPeerConnections(for: transferID)
                } else {
                    requestNextPeerRangeIfNeeded(for: transferID, endpoint: endpoint)
                }
            } catch {
                emitNetworkLog("eD2k peer block write failed: \(error.localizedDescription)")
                cancelPeerConnection(for: transferID, endpoint: endpoint)
            }
        case .fileRequestAnswerNoFile:
            emitNetworkLog("eD2k peer does not have requested file: \(endpoint.address)")
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        case .acceptUploadRequest:
            emitNetworkLog("eD2k peer granted upload slot: \(endpoint.address)")
            markTransferDownloading(transferID)
            sendInitialPeerDataRequests(transferID: transferID, endpoint: endpoint)
        case .queueRank(let rank):
            emitNetworkLog("eD2k peer queued us at rank \(rank): \(endpoint.address)")
        case .unhandledPacket(let packet):
            emitNetworkLog("eD2k peer unhandled packet: opcode 0x\(String(format: "%02X", packet.opcode))")
        }
    }

    private func applyPeerSourceExchangeAnswer(
        _ answer: ED2KPeerSourceExchangeAnswer,
        transferID: UUID,
        endpoint: ED2KPeerEndpoint
    ) {
        let shouldStartDownloads = withLock { () -> Bool in
            guard let index = state.transfers.firstIndex(where: { $0.id == transferID }) else {
                return false
            }

            let expectedHash = state.transfers[index].ed2kHash
            guard answer.fileHash.hexadecimalString.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                emitNetworkLog("eD2k peer source-exchange ignored with mismatched hash from \(endpoint.address)")
                return false
            }

            let directSources = answer.sources.compactMap { source -> ED2KFoundSource? in
                let foundSource = ED2KFoundSource(clientID: source.clientID, clientPort: source.clientPort)
                return peerEndpoint(from: foundSource) == nil ? nil : foundSource
            }

            let directCount = rememberPeerSourcesLocked(
                directSources,
                fileHash: answer.fileHash,
                for: transferID
            )
            guard directCount > 0 else {
                return false
            }

            let previous = state.transfers[index]
            let knownDirectEndpointCount = peerSourceQueues[transferID]?.count ?? directCount
            state.transfers[index].availability = max(
                state.transfers[index].availability,
                knownDirectEndpointCount
            )
            state.transfers[index].sources = max(
                state.transfers[index].sources,
                knownDirectEndpointCount
            )

            let transfer = state.transfers[index]
            if transfer != previous {
                try? persist(transfer)
                recordLocked(.transferUpdated, transfer: transfer)
            }
            return true
        }

        if shouldStartDownloads {
            startPeerDownloadsIfPossible(for: transferID)
        }
    }

    private func sendPeerDownloadNegotiation(
        transferID: UUID,
        fileHash: Data,
        endpoint: ED2KPeerEndpoint
    ) {
        guard let connection = withLock({ peerConnections[transferID]?[endpoint] }) else {
            return
        }

        var ok = connection.sendFileRequest(fileHash: fileHash)
        ok = connection.sendSetRequestFileID(fileHash: fileHash) && ok
        _ = connection.sendSourceExchangeRequest(fileHash: fileHash)
        ok = connection.sendStartUploadRequest(fileHash: fileHash) && ok
        if ok == false {
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        }
    }

    private func sendInitialPeerDataRequests(
        transferID: UUID,
        endpoint: ED2KPeerEndpoint
    ) {
        typealias PeerInitialRequestState = (connection: ED2KPeerTCPConnection, fileHash: Data, initialRange: ED2KPartRange, shouldRequestHashSet: Bool)
        guard let requestState: PeerInitialRequestState = withLock({
            guard let connection = peerConnections[transferID]?[endpoint],
                  let initialRange = peerInflightRanges[transferID]?[endpoint],
                  let transfer = state.transfers.first(where: { $0.id == transferID }),
                  let fileHash = Data(hexadecimalString: transfer.ed2kHash) else {
                return nil
            }

            return (
                connection,
                fileHash,
                initialRange,
                reservePartHashSetRequestIfNeededLocked(for: transfer, endpoint: endpoint)
            )
        }) else {
            return
        }

        if requestState.shouldRequestHashSet {
            if requestState.connection.sendPartHashSetRequest(fileHash: requestState.fileHash) == false {
                withLock {
                    clearPartHashSetRequestOwnerLocked(for: transferID, endpoint: endpoint)
                }
                requestPartHashSetFromActivePeerIfNeeded(for: transferID, excluding: [endpoint])
            }
        }

        if requestState.connection.sendPartRequest(fileHash: requestState.fileHash, ranges: [requestState.initialRange]) == false {
            handlePeerConnectionLoss(for: transferID, endpoint: endpoint)
        }
    }

    private func markTransferDownloading(_ transferID: UUID) {
        withLock {
            guard let index = state.transfers.firstIndex(where: { $0.id == transferID }),
                  state.transfers[index].status == .queued else {
                return
            }

            state.transfers[index].status = .downloading
            state.transfers[index].downloadSpeedBytesPerSecond = 0
            try? persist(state.transfers[index])
            recordLocked(.transferUpdated, transfer: state.transfers[index])
        }
    }

    private func makePeerDownloadPlanLocked(transfer: CoreTransfer) -> PeerDownloadPlan? {
        let activeConnections = peerConnections[transfer.id] ?? [:]
        pruneExpiredPeerSourceCooldownsLocked(for: transfer.id)
        guard activeConnections.count < Self.maxConcurrentPeerConnectionsPerTransfer else {
            return nil
        }

        guard let fileHash = Data(hexadecimalString: transfer.ed2kHash) else {
            emitNetworkLog("eD2k peer connect skipped for invalid hash: \(transfer.ed2kHash)")
            return nil
        }

        guard let endpoint = peerSourceQueues[transfer.id]?.first(where: {
            activeConnections[$0] == nil && isPeerAvailableForRetryLocked($0, transferID: transfer.id)
        }) else {
            if hasPendingServerCallbackRequestLocked(for: transfer.id) == false {
                emitNetworkLog("eD2k peer connect skipped without a direct source endpoint for \(transfer.ed2kHash)")
            } else {
                emitNetworkLog("eD2k peer waiting for server callback for \(transfer.ed2kHash)")
            }
            return nil
        }

        guard let range = reserveNextPeerRequestRangeLocked(for: transfer, endpoint: endpoint) else {
            return nil
        }

        return PeerDownloadPlan(
            transferID: transfer.id,
            fileHash: fileHash,
            endpoint: endpoint,
            range: range
        )
    }

    private func applyServerCallbackRequestedLocked(_ endpoint: ED2KPeerEndpoint) -> PeerDownloadPlan? {
        guard let request = activeServerCallbackRequest else {
            emitNetworkLog("eD2k server callback requested without an active queued source: \(endpoint.address)")
            return nil
        }

        guard let transfer = state.transfers.first(where: { $0.id == request.transferID }) else {
            activeServerCallbackRequest = nil
            emitNetworkLog("eD2k server callback requested for missing transfer \(request.transferID.uuidString)")
            return nil
        }

        let activeConnections = peerConnections[transfer.id] ?? [:]
        guard activeConnections.count < Self.maxConcurrentPeerConnectionsPerTransfer else {
            requeueActiveServerCallbackRequestLocked()
            emitNetworkLog("eD2k server callback deferred for \(transfer.ed2kHash) because the transfer already has \(activeConnections.count) peer connection(s)")
            return nil
        }

        guard transfer.status == .queued || transfer.status == .downloading else {
            activeServerCallbackRequest = nil
            emitNetworkLog("eD2k server callback ignored for \(transfer.ed2kHash) because transfer is \(transfer.status.rawValue)")
            return nil
        }

        guard let range = reserveNextPeerRequestRangeLocked(for: transfer, endpoint: endpoint) else {
            requeueActiveServerCallbackRequestLocked()
            emitNetworkLog("eD2k server callback had no available range for \(transfer.ed2kHash)")
            return nil
        }

        activeServerCallbackRequest = nil
        return PeerDownloadPlan(
            transferID: request.transferID,
            fileHash: request.fileHash,
            endpoint: endpoint,
            range: range
        )
    }

    private func hasPendingServerCallbackRequestLocked(for transferID: UUID) -> Bool {
        if activeServerCallbackRequest?.transferID == transferID {
            return true
        }
        return pendingServerCallbackRequests.contains(where: { $0.transferID == transferID })
    }

    private func requeueActiveServerCallbackRequestLocked() {
        guard let request = activeServerCallbackRequest else {
            return
        }

        activeServerCallbackRequest = nil
        if pendingServerCallbackRequests.contains(request) == false {
            pendingServerCallbackRequests.insert(request, at: 0)
        }
    }

    @discardableResult
    private func rememberPeerSourcesLocked(
        _ sources: [ED2KFoundSource],
        fileHash: Data,
        for transferID: UUID
    ) -> Int {
        let endpoints = sources.compactMap(peerEndpoint)
        let lowIDCount = sources.count - endpoints.count
        if lowIDCount > 0 {
            let queuedCount = queueServerCallbackRequestsLocked(sources, fileHash: fileHash, transferID: transferID)
            if queuedCount > 0 {
                emitNetworkLog("eD2k \(queuedCount) fuente(s) LowID encoladas para callback de servidor.")
            }
        }

        guard endpoints.isEmpty == false else {
            return 0
        }

        var queuedEndpoints = peerSourceQueues[transferID] ?? []
        var failureCounts = peerSourceFailures[transferID] ?? [:]
        var cooldowns = peerSourceCooldowns[transferID] ?? [:]
        for endpoint in endpoints {
            if queuedEndpoints.contains(endpoint) == false {
                queuedEndpoints.append(endpoint)
                failureCounts.removeValue(forKey: endpoint)
                cooldowns.removeValue(forKey: endpoint)
            }
        }
        peerSourceFailures[transferID] = failureCounts
        peerSourceCooldowns[transferID] = cooldowns
        peerSourceQueues[transferID] = queuedEndpoints
        reorderPeerSourceQueueLocked(for: transferID)
        persistPeerSourceStateLocked(for: transferID)
        return endpoints.count
    }

    private func queueServerCallbackRequestsLocked(
        _ sources: [ED2KFoundSource],
        fileHash: Data,
        transferID: UUID
    ) -> Int {
        var queuedCount = 0
        for source in sources where peerEndpoint(from: source) == nil {
            guard source.clientPort > 0 else {
                continue
            }

            let request = ServerCallbackRequest(
                transferID: transferID,
                fileHash: fileHash,
                sourceClientID: source.clientID,
                sourceClientPort: source.clientPort,
                serverEndpoint: activeServerEndpoint
            )

            let alreadyQueued = pendingServerCallbackRequests.contains(request)
                || activeServerCallbackRequest == request
            guard alreadyQueued == false else {
                continue
            }

            pendingServerCallbackRequests.append(request)
            queuedCount += 1
        }
        return queuedCount
    }

    private func reorderPeerSourceQueueLocked(for transferID: UUID) {
        let queuedEndpoints = peerSourceQueues[transferID] ?? []
        let failureCounts = peerSourceFailures[transferID] ?? [:]
        let cooldowns = peerSourceCooldowns[transferID] ?? [:]
        peerSourceQueues[transferID] = queuedEndpoints.enumerated().sorted { lhs, rhs in
            let lhsCoolingDown = cooldowns[lhs.element].map { $0 > Date() } ?? false
            let rhsCoolingDown = cooldowns[rhs.element].map { $0 > Date() } ?? false
            if lhsCoolingDown != rhsCoolingDown {
                return lhsCoolingDown == false
            }
            let lhsFailures = failureCounts[lhs.element, default: 0]
            let rhsFailures = failureCounts[rhs.element, default: 0]
            if lhsFailures == rhsFailures {
                return lhs.offset < rhs.offset
            }
            return lhsFailures < rhsFailures
        }.map(\.element)
    }

    private func isPeerAvailableForRetryLocked(_ endpoint: ED2KPeerEndpoint, transferID: UUID) -> Bool {
        if let cooldownUntil = peerSourceCooldowns[transferID]?[endpoint] {
            return cooldownUntil <= Date()
        }
        return true
    }

    private func peerFailureCooldownInterval(for failureCount: Int) -> TimeInterval {
        let normalizedFailureCount = max(1, failureCount)
        let multiplier = pow(2.0, Double(normalizedFailureCount - 1))
        return min(Self.peerFailureCooldownBase * multiplier, Self.peerFailureCooldownMax)
    }

    private func pruneExpiredPeerSourceCooldownsLocked(for transferID: UUID, now: Date = Date()) {
        guard var cooldowns = peerSourceCooldowns[transferID], cooldowns.isEmpty == false else {
            return
        }

        let expiredEndpoints = cooldowns.compactMap { endpoint, cooldownUntil in
            cooldownUntil <= now ? endpoint : nil
        }
        guard expiredEndpoints.isEmpty == false else {
            return
        }

        var failureCounts = peerSourceFailures[transferID] ?? [:]
        for endpoint in expiredEndpoints {
            cooldowns.removeValue(forKey: endpoint)
            if failureCounts[endpoint, default: 0] > 0 {
                failureCounts[endpoint] = 0
            }
        }
        peerSourceCooldowns[transferID] = cooldowns
        peerSourceFailures[transferID] = failureCounts
        reorderPeerSourceQueueLocked(for: transferID)
        persistPeerSourceStateLocked(for: transferID)
    }

    private func shouldRequestPartHashSetLocked(for transfer: CoreTransfer) -> Bool {
        transfer.partHashes.isEmpty && expectedPartCount(for: transfer.sizeInBytes) > 1
    }

    private func reservePartHashSetRequestIfNeededLocked(
        for transfer: CoreTransfer,
        endpoint: ED2KPeerEndpoint
    ) -> Bool {
        guard shouldRequestPartHashSetLocked(for: transfer),
              peerPartHashSetRequestOwners[transfer.id] == nil else {
            return false
        }

        peerPartHashSetRequestOwners[transfer.id] = endpoint
        return true
    }

    private func reserveNextPeerRequestRangeLocked(
        for transfer: CoreTransfer,
        endpoint: ED2KPeerEndpoint
    ) -> ED2KPartRange? {
        let activeInflightRanges = activePeerInflightRangesLocked(for: transfer.id)
        let completedRanges: [CoreByteRange]
        if let transferStore, let record = try? transferStore.loadRecord(for: transfer.id) {
            completedRanges = record.chunkMap.writtenRanges
        } else if transfer.completedBytes > 0 {
            completedRanges = [CoreByteRange(offset: 0, length: transfer.completedBytes)]
        } else {
            completedRanges = []
        }

        if let rarityScheduler,
           let fileHash = Data(hexadecimalString: transfer.ed2kHash) {
            let inflightCoreRanges = activeInflightRanges.map {
                CoreByteRange(offset: UInt64($0.startOffset), length: UInt64($0.endOffset - $0.startOffset))
            }
            let allBusy = normalizedPeerRanges(completedRanges + inflightCoreRanges)
            let closedBusy: [ClosedRange<UInt64>] = allBusy.map {
                $0.offset...($0.offset + $0.length - 1)
            }
            if let rarest = rarityScheduler.getNextPart(
                for: fileHash,
                completedRanges: closedBusy,
                partAvailability: [:]
            ) {
                let partStart = rarest.start
                let partEnd = min(rarest.end + 1, transfer.sizeInBytes)
                let candidateEnd = min(partEnd, partStart + Self.peerRequestBlockSize)
                let range = ED2KPartRange(startOffset: partStart, endOffset: candidateEnd)
                if range.endOffset > range.startOffset {
                    var inflightRanges = peerInflightRanges[transfer.id] ?? [:]
                    inflightRanges[endpoint] = range
                    peerInflightRanges[transfer.id] = inflightRanges
                    var inflightTimestamps = peerInflightRangeTimestamps[transfer.id] ?? [:]
                    inflightTimestamps[endpoint] = Date()
                    peerInflightRangeTimestamps[transfer.id] = inflightTimestamps
                    persistPeerInflightStateLocked(for: transfer.id)
                    return range
                }
            }
        }

        guard let range = nextPeerRequestRangeCandidateLocked(
            fileSize: transfer.sizeInBytes,
            completedRanges: completedRanges,
            inflightRanges: activeInflightRanges,
            transferID: transfer.id
        ) else {
            return nil
        }

        var inflightRanges = peerInflightRanges[transfer.id] ?? [:]
        inflightRanges[endpoint] = range
        peerInflightRanges[transfer.id] = inflightRanges
        var inflightTimestamps = peerInflightRangeTimestamps[transfer.id] ?? [:]
        inflightTimestamps[endpoint] = Date()
        peerInflightRangeTimestamps[transfer.id] = inflightTimestamps
        persistPeerInflightStateLocked(for: transfer.id)
        return range
    }

    private func nextPeerRequestRangeCandidateLocked(
        fileSize: UInt64,
        completedRanges: [CoreByteRange],
        inflightRanges: [ED2KPartRange],
        transferID: UUID,
        now: Date = Date()
    ) -> ED2KPartRange? {
        pruneExpiredPeerChunkRetryCooldownsLocked(for: transferID, now: now)
        let reservedRanges = inflightRanges.map {
            CoreByteRange(
                offset: UInt64($0.startOffset),
                length: UInt64($0.endOffset - $0.startOffset)
            )
        }
        let coveredRanges = normalizedPeerRanges(completedRanges + reservedRanges)
        var fallback: ED2KPartRange?
        var cursor: UInt64 = 0

        for coveredRange in coveredRanges {
            if coveredRange.offset > cursor,
               let candidate = nextPeerRequestRangeCandidateLocked(
                    gapStart: cursor,
                    gapEnd: coveredRange.offset,
                    transferID: transferID,
                    now: now,
                    fallback: &fallback
               ) {
                return candidate
            }
            cursor = max(cursor, coveredRange.endOffset)
            if cursor >= fileSize {
                return fallback
            }
        }

        if cursor < fileSize,
           let candidate = nextPeerRequestRangeCandidateLocked(
                gapStart: cursor,
                gapEnd: fileSize,
                transferID: transferID,
                now: now,
                fallback: &fallback
           ) {
            return candidate
        }

        return fallback
    }

    private func nextPeerRequestRangeCandidateLocked(
        gapStart: UInt64,
        gapEnd: UInt64,
        transferID: UUID,
        now: Date,
        fallback: inout ED2KPartRange?
    ) -> ED2KPartRange? {
        var candidateStart = gapStart

        while candidateStart < gapEnd {
            let candidateEnd = min(gapEnd, candidateStart + Self.peerRequestBlockSize)
            let start = candidateStart
            let end = candidateEnd
            let candidate = ED2KPartRange(startOffset: start, endOffset: end)
            let retryState = peerChunkRetryStates[transferID]?[PeerChunkRetryKey(range: candidate)]
            if fallback == nil {
                fallback = candidate
            }
            if retryState?.cooldownUntil.map({ $0 > now }) != true {
                return candidate
            }

            candidateStart = candidateEnd
        }

        return nil
    }

    private func requestNextPeerRangeIfNeeded(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        typealias PeerRangeRequest = (ED2KPeerTCPConnection, Data, ED2KPartRange)
        guard let nextRequest: PeerRangeRequest = withLock({
            guard let connection = peerConnections[transferID]?[endpoint],
                  let transfer = state.transfers.first(where: { $0.id == transferID }),
                  transfer.status == .downloading || transfer.status == .queued,
                  let fileHash = Data(hexadecimalString: transfer.ed2kHash),
                  let range = reserveNextPeerRequestRangeLocked(for: transfer, endpoint: endpoint) else {
                return nil
            }

            return (connection, fileHash, range)
        }) else {
            return
        }

        emitNetworkLog(
            "eD2k peer requesting siguiente rango \(nextRequest.2.startOffset)-\(nextRequest.2.endOffset) from \(endpoint.address)"
        )
        if nextRequest.0.sendPartRequest(fileHash: nextRequest.1, ranges: [nextRequest.2]) == false {
            cancelPeerConnection(for: transferID, endpoint: endpoint)
        }
    }

    private func handlePeerConnectionLoss(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        let lostRange = withLock { peerInflightRanges[transferID]?[endpoint] }
        removePeerConnection(for: transferID, endpoint: endpoint)
        withLock {
            if let lostRange {
                notePeerChunkRetryFailureLocked(for: transferID, range: lostRange)
            }
            let failureCount = (peerSourceFailures[transferID] ?? [:])[endpoint, default: 0] + 1
            let currentFailures = peerSourceFailures[transferID] ?? [:]
            var updatedFailures = currentFailures
            updatedFailures[endpoint] = failureCount
            peerSourceFailures[transferID] = updatedFailures
            var cooldowns = peerSourceCooldowns[transferID] ?? [:]
            cooldowns[endpoint] = Date().addingTimeInterval(peerFailureCooldownInterval(for: failureCount))
            peerSourceCooldowns[transferID] = cooldowns
            if var queue = peerSourceQueues[transferID] {
                if queue.contains(endpoint) == false {
                    queue.append(endpoint)
                    peerSourceQueues[transferID] = queue
                }
            } else {
                peerSourceQueues[transferID] = [endpoint]
            }
            reorderPeerSourceQueueLocked(for: transferID)
            persistPeerSourceStateLocked(for: transferID)
        }
        requestPartHashSetFromActivePeerIfNeeded(for: transferID, excluding: [endpoint])

        if startPeerFailoverIfNeeded(for: transferID) == false,
           let transfer = withLock({ state.transfers.first(where: { $0.id == transferID }) }) {
            emitNetworkLog("eD2k peer agotado en \(endpoint.address), pidiendo mas fuentes para \(transfer.ed2kHash)")
            requestSourcesIfPossible(for: transfer, force: true)
        }
    }

    private func handlePartHashSetRequestFailure(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        let shouldRetry = withLock {
            clearPartHashSetRequestOwnerLocked(for: transferID, endpoint: endpoint)
            guard let transfer = state.transfers.first(where: { $0.id == transferID }) else {
                return false
            }
            return shouldRequestPartHashSetLocked(for: transfer)
        }

        guard shouldRetry else {
            return
        }

        requestPartHashSetFromActivePeerIfNeeded(for: transferID, excluding: [endpoint])
    }

    @discardableResult
    private func startPeerFailoverIfNeeded(for transferID: UUID) -> Bool {
        let plan: PeerDownloadPlan? = withLock {
            guard let transfer = state.transfers.first(where: { $0.id == transferID }),
                  transfer.status == .queued || transfer.status == .downloading,
                  transfer.completedBytes < transfer.sizeInBytes else {
                return nil
            }

            return makePeerDownloadPlanLocked(transfer: transfer)
        }
        guard let plan else {
            return false
        }

        emitNetworkLog("eD2k peer failover attempting \(plan.endpoint.address) for \(plan.transferID.uuidString)")
        startPeerDownload(using: plan)
        startPeerDownloadsIfPossible(for: transferID)
        return true
    }

    private func firstMissingOffset(
        in chunkMap: CoreChunkMap,
        reserving inflightRanges: [CoreByteRange]
    ) -> UInt64 {
        firstMissingOffset(
            in: chunkMap.fileSizeInBytes,
            completedBytes: chunkMap.completedBytes,
            reserving: chunkMap.writtenRanges + inflightRanges
        )
    }

    private func firstMissingOffset(
        in fileSize: UInt64,
        completedBytes: UInt64,
        reserving ranges: [CoreByteRange]
    ) -> UInt64 {
        if ranges.isEmpty {
            return min(completedBytes, fileSize)
        }

        var cursor: UInt64 = 0
        for range in normalizedPeerRanges(ranges) {
            if range.offset > cursor {
                return cursor
            }
            cursor = max(cursor, range.endOffset)
            if cursor >= fileSize {
                return fileSize
            }
        }
        return min(cursor, fileSize)
    }

    private func activePeerInflightRangesLocked(for transferID: UUID) -> [ED2KPartRange] {
        pruneExpiredPeerInflightRangesLocked(for: transferID)
        return peerInflightRanges[transferID].map { Array($0.values) } ?? []
    }

    private func pruneExpiredPeerInflightRangesLocked(for transferID: UUID, now: Date = Date()) {
        guard let timestamps = peerInflightRangeTimestamps[transferID], timestamps.isEmpty == false else {
            return
        }

        let expirationInterval = Self.peerInflightReservationTTL
        let expiredEndpoints = timestamps.compactMap { endpoint, reservedAt in
            now.timeIntervalSince(reservedAt) >= expirationInterval ? endpoint : nil
        }

        guard expiredEndpoints.isEmpty == false else {
            return
        }

        for endpoint in expiredEndpoints {
            clearPeerInflightRangeLocked(for: transferID, endpoint: endpoint)
        }
    }

    private func normalizedPeerRanges(_ ranges: [CoreByteRange]) -> [CoreByteRange] {
        let sortedRanges = ranges
            .filter { $0.length > 0 }
            .sorted { lhs, rhs in
                if lhs.offset == rhs.offset {
                    return lhs.length < rhs.length
                }
                return lhs.offset < rhs.offset
            }

        return sortedRanges.reduce(into: []) { output, range in
            guard var lastRange = output.popLast() else {
                output.append(range)
                return
            }

            if range.offset <= lastRange.endOffset {
                let endOffset = max(lastRange.endOffset, range.endOffset)
                lastRange.length = endOffset - lastRange.offset
                output.append(lastRange)
            } else {
                output.append(lastRange)
                output.append(range)
            }
        }
    }

    private func peerEndpoint(from source: ED2KFoundSource) -> ED2KPeerEndpoint? {
        guard source.clientPort > 0 else {
            return nil
        }
        guard ED2KClientID.isHighID(source.clientID) else {
            return nil
        }

        let octets = [
            UInt8(source.clientID & 0x000000FF),
            UInt8((source.clientID >> 8) & 0x000000FF),
            UInt8((source.clientID >> 16) & 0x000000FF),
            UInt8((source.clientID >> 24) & 0x000000FF)
        ]

        guard octets.contains(where: { $0 != 0 }) else {
            return nil
        }

        return ED2KPeerEndpoint(
            host: octets.map(String.init).joined(separator: "."),
            port: source.clientPort
        )
    }

    private func clearPeerInflightRange(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        withLock {
            guard var inflightRanges = peerInflightRanges[transferID] else {
                return
            }
            inflightRanges.removeValue(forKey: endpoint)
            if inflightRanges.isEmpty {
                peerInflightRanges.removeValue(forKey: transferID)
            } else {
                peerInflightRanges[transferID] = inflightRanges
            }
        }
    }

    private func cancelPeerConnection(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        let connection: ED2KPeerTCPConnection? = withLock {
            clearPeerInflightRangeLocked(for: transferID, endpoint: endpoint)
            clearPartHashSetRequestOwnerLocked(for: transferID, endpoint: endpoint)
            peerSpeedTrackers.removeValue(forKey: PeerSpeedKey(transferID: transferID, endpoint: endpoint))
            guard var transferConnections = peerConnections[transferID] else {
                return nil
            }
            let connection = transferConnections.removeValue(forKey: endpoint)
            if transferConnections.isEmpty {
                peerConnections.removeValue(forKey: transferID)
            } else {
                peerConnections[transferID] = transferConnections
            }
            return connection
        }
        connection?.cancel()
    }

    private func cancelPeerConnections(for transferID: UUID) {
        let connections: [ED2KPeerTCPConnection] = withLock {
            peerInflightRanges.removeValue(forKey: transferID)
            peerInflightRangeTimestamps.removeValue(forKey: transferID)
            peerPartHashSetRequestOwners.removeValue(forKey: transferID)
            removeDownloadSpeedStateLocked(for: transferID)
            let removedConnections = peerConnections.removeValue(forKey: transferID) ?? [:]
            return Array(removedConnections.values)
        }
        connections.forEach { $0.cancel() }
    }

    private func removePeerConnection(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        withLock {
            clearPeerInflightRangeLocked(for: transferID, endpoint: endpoint)
            clearPartHashSetRequestOwnerLocked(for: transferID, endpoint: endpoint)
            peerSpeedTrackers.removeValue(forKey: PeerSpeedKey(transferID: transferID, endpoint: endpoint))
            guard var transferConnections = peerConnections[transferID] else {
                return
            }
            transferConnections.removeValue(forKey: endpoint)
            if transferConnections.isEmpty {
                peerConnections.removeValue(forKey: transferID)
            } else {
                peerConnections[transferID] = transferConnections
            }
        }
    }

    private func clearPeerInflightRangeLocked(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        guard var inflightRanges = peerInflightRanges[transferID] else {
            if var inflightTimestamps = peerInflightRangeTimestamps[transferID] {
                inflightTimestamps.removeValue(forKey: endpoint)
                if inflightTimestamps.isEmpty {
                    peerInflightRangeTimestamps.removeValue(forKey: transferID)
                } else {
                    peerInflightRangeTimestamps[transferID] = inflightTimestamps
                }
                persistPeerInflightStateLocked(for: transferID)
            }
            return
        }
        inflightRanges.removeValue(forKey: endpoint)
        if inflightRanges.isEmpty {
            peerInflightRanges.removeValue(forKey: transferID)
        } else {
            peerInflightRanges[transferID] = inflightRanges
        }

        if var inflightTimestamps = peerInflightRangeTimestamps[transferID] {
            inflightTimestamps.removeValue(forKey: endpoint)
            if inflightTimestamps.isEmpty {
                peerInflightRangeTimestamps.removeValue(forKey: transferID)
            } else {
                peerInflightRangeTimestamps[transferID] = inflightTimestamps
            }
        }

        persistPeerInflightStateLocked(for: transferID)
    }

    private func clearPartHashSetRequestOwnerLocked(for transferID: UUID, endpoint: ED2KPeerEndpoint) {
        guard peerPartHashSetRequestOwners[transferID] == endpoint else {
            return
        }

        peerPartHashSetRequestOwners.removeValue(forKey: transferID)
    }

    private func requestPartHashSetFromActivePeerIfNeeded(
        for transferID: UUID,
        excluding excludedEndpoints: Set<ED2KPeerEndpoint> = []
    ) {
        typealias PeerPartHashSetCandidate = (
            endpoint: ED2KPeerEndpoint,
            connection: ED2KPeerTCPConnection,
            fileHash: Data
        )
        var attemptedEndpoints = excludedEndpoints

        while true {
            guard let candidate: PeerPartHashSetCandidate = withLock({
                guard peerPartHashSetRequestOwners[transferID] == nil,
                      let transfer = state.transfers.first(where: { $0.id == transferID }),
                      shouldRequestPartHashSetLocked(for: transfer),
                      let fileHash = Data(hexadecimalString: transfer.ed2kHash),
                      let connections = peerConnections[transferID] else {
                    return nil
                }

                for (endpoint, connection) in connections where attemptedEndpoints.contains(endpoint) == false {
                    peerPartHashSetRequestOwners[transferID] = endpoint
                    return (endpoint, connection, fileHash)
                }

                return nil
            }) else {
                return
            }

            if candidate.connection.sendPartHashSetRequest(fileHash: candidate.fileHash) {
                return
            }

            attemptedEndpoints.insert(candidate.endpoint)
            withLock {
                clearPartHashSetRequestOwnerLocked(for: transferID, endpoint: candidate.endpoint)
            }
        }
    }

    private func persistPeerSourceStateLocked(for transferID: UUID) {
        guard transferStore != nil else {
            return
        }

        let failureCounts = peerSourceFailures[transferID] ?? [:]
        let cooldowns = peerSourceCooldowns[transferID] ?? [:]
        let activeEndpoints = Array(peerConnections[transferID]?.keys ?? [:].keys)
        var orderedEndpoints = peerSourceQueues[transferID] ?? []
        for endpoint in activeEndpoints where orderedEndpoints.contains(endpoint) == false {
            orderedEndpoints.append(endpoint)
        }
        for endpoint in failureCounts.keys where orderedEndpoints.contains(endpoint) == false {
            orderedEndpoints.append(endpoint)
        }

        let bookmarks = orderedEndpoints.map {
            CorePeerSourceBookmark(
                endpoint: $0,
                failureCount: failureCounts[$0, default: 0],
                cooldownUntil: cooldowns[$0]
            )
        }

        do {
            _ = try transferStore?.updatePeerSourceBookmarks(transferID: transferID, bookmarks: bookmarks)
        } catch {
            emitNetworkLog("eD2k peer source state persistence failed: \(error.localizedDescription)")
        }
    }

    private func persistPeerInflightStateLocked(for transferID: UUID) {
        guard transferStore != nil else {
            return
        }

        let inflightRanges = peerInflightRanges[transferID] ?? [:]
        let inflightTimestamps = peerInflightRangeTimestamps[transferID] ?? [:]
        let bookmarks: [CorePeerInflightBookmark] = inflightRanges.compactMap { entry in
            let (endpoint, range) = entry
            guard let reservedAt = inflightTimestamps[endpoint] else {
                return nil
            }
            return CorePeerInflightBookmark(
                endpoint: endpoint,
                startOffset: range.startOffset,
                endOffset: range.endOffset,
                reservedAt: reservedAt
            )
        }.sorted { lhs, rhs in
            if lhs.reservedAt == rhs.reservedAt {
                return lhs.endpoint.address < rhs.endpoint.address
            }
            return lhs.reservedAt < rhs.reservedAt
        }

        do {
            _ = try transferStore?.updatePeerInflightBookmarks(transferID: transferID, bookmarks: bookmarks)
        } catch {
            emitNetworkLog("eD2k peer inflight state persistence failed: \(error.localizedDescription)")
        }
    }

    private func notePeerChunkRetryFailureLocked(for transferID: UUID, range: ED2KPartRange, now: Date = Date()) {
        let key = PeerChunkRetryKey(range: range)
        var retryStates = peerChunkRetryStates[transferID] ?? [:]
        let nextFailureCount = retryStates[key].map { max(0, $0.failureCount) + 1 } ?? 1
        retryStates[key] = PeerChunkRetryState(
            failureCount: nextFailureCount,
            cooldownUntil: now.addingTimeInterval(peerFailureCooldownInterval(for: nextFailureCount)),
            lastFailureAt: now
        )
        peerChunkRetryStates[transferID] = retryStates
        persistPeerChunkRetryStateLocked(for: transferID)
    }

    private func clearPeerChunkRetryStateLocked(for transferID: UUID, overlapping range: ED2KPartRange) {
        guard var retryStates = peerChunkRetryStates[transferID], retryStates.isEmpty == false else {
            return
        }

        let overlappingKeys = retryStates.keys.filter {
            UInt64($0.startOffset) < UInt64(range.endOffset) && UInt64($0.endOffset) > UInt64(range.startOffset)
        }
        guard overlappingKeys.isEmpty == false else {
            return
        }

        for key in overlappingKeys {
            retryStates.removeValue(forKey: key)
        }

        if retryStates.isEmpty {
            peerChunkRetryStates.removeValue(forKey: transferID)
        } else {
            peerChunkRetryStates[transferID] = retryStates
        }
        persistPeerChunkRetryStateLocked(for: transferID)
    }

    private func pruneExpiredPeerChunkRetryCooldownsLocked(for transferID: UUID, now: Date = Date()) {
        guard var retryStates = peerChunkRetryStates[transferID], retryStates.isEmpty == false else {
            return
        }

        var didChange = false
        for key in retryStates.keys {
            guard let cooldownUntil = retryStates[key]?.cooldownUntil,
                  cooldownUntil <= now else {
                continue
            }

            retryStates[key]?.cooldownUntil = nil
            didChange = true
        }

        guard didChange else {
            return
        }

        peerChunkRetryStates[transferID] = retryStates
        persistPeerChunkRetryStateLocked(for: transferID)
    }

    private func persistPeerChunkRetryStateLocked(for transferID: UUID) {
        guard transferStore != nil else {
            return
        }

        let bookmarks = (peerChunkRetryStates[transferID] ?? [:]).map { entry in
            let (key, state) = entry
            return CorePeerChunkRetryBookmark(
                startOffset: key.startOffset,
                endOffset: key.endOffset,
                failureCount: state.failureCount,
                cooldownUntil: state.cooldownUntil,
                lastFailureAt: state.lastFailureAt
            )
        }.sorted { lhs, rhs in
            if lhs.startOffset == rhs.startOffset {
                return lhs.endOffset < rhs.endOffset
            }
            return lhs.startOffset < rhs.startOffset
        }

        do {
            _ = try transferStore?.updatePeerChunkRetryBookmarks(transferID: transferID, bookmarks: bookmarks)
        } catch {
            emitNetworkLog("eD2k peer chunk retry persistence failed: \(error.localizedDescription)")
        }
    }

    private func applyPeerPartHashSet(
        _ hashSet: ED2KPartHashSet,
        transferID: UUID,
        endpoint: ED2KPeerEndpoint
    ) {
        typealias PeerPartHashSetUpdate = (transfer: CoreTransfer?, shouldRetry: Bool)
        do {
            let update: PeerPartHashSetUpdate = try withLock {
                guard let index = state.transfers.firstIndex(where: { $0.id == transferID }) else {
                    return (nil, false)
                }

                clearPartHashSetRequestOwnerLocked(for: transferID, endpoint: endpoint)
                let expectedHash = state.transfers[index].ed2kHash
                let receivedHash = hashSet.fileHash.hexadecimalString
                guard expectedHash == receivedHash else {
                    emitNetworkLog("eD2k peer hashset ignored for mismatched file hash \(receivedHash)")
                    return (nil, shouldRequestPartHashSetLocked(for: state.transfers[index]))
                }

                let expectedPartCount = expectedPartCount(for: state.transfers[index].sizeInBytes)
                guard hashSet.partHashes.count == expectedPartCount else {
                    emitNetworkLog("eD2k peer hashset ignored for \(expectedHash): expected \(expectedPartCount) part hash(es), got \(hashSet.partHashes.count)")
                    return (nil, shouldRequestPartHashSetLocked(for: state.transfers[index]))
                }

                if state.transfers[index].partHashes.isEmpty == false {
                    return (nil, false)
                }

                state.transfers[index].partHashes = hashSet.partHashes.map(\.hexadecimalString)
                let reconciledTransfer = try reconcilePersistedTransferLocked(state.transfers[index])
                state.transfers[index] = reconciledTransfer
                recordLocked(.transferUpdated, transfer: reconciledTransfer)
                return (reconciledTransfer, false)
            }

            if update.shouldRetry {
                requestPartHashSetFromActivePeerIfNeeded(for: transferID, excluding: [endpoint])
            }

            if let transfer = update.transfer,
               transfer.status == CoreTransferStatus.completed || transfer.status == CoreTransferStatus.failed {
                cancelPeerConnections(for: transferID)
                if transfer.status == .completed,
                   let hashData = Data(hexadecimalString: transfer.ed2kHash) {
                    knownFileList?.recordDownload(hash: hashData, fileName: transfer.fileName, fileSize: transfer.sizeInBytes)
                    try? knownFileList?.save()
                }
            }
        } catch {
            emitNetworkLog("eD2k peer hashset reconciliation failed: \(error.localizedDescription)")
        }
    }

    private func reconcilePersistedTransferLocked(_ transfer: CoreTransfer) throws -> CoreTransfer {
        do {
            if let reconciled = try transferStore?.reconcileTransferMetadata(transfer) {
                return reconciled.transfer
            }

            try transferStore?.upsert(transfer)
            return transfer
        } catch {
            throw CoreServiceError.persistence(error.localizedDescription)
        }
    }

    private func expectedPartCount(for fileSize: UInt64) -> Int {
        guard fileSize > 0 else {
            return 0
        }

        return Int((fileSize + CoreChunkMap.ed2kChunkSize - 1) / CoreChunkMap.ed2kChunkSize)
    }

    private func setPreferredServerLocked(_ endpoint: ED2KServerEndpoint) {
        var didChange = false

        if let existingIndex = state.servers.firstIndex(where: { $0.endpoint == endpoint }) {
            for index in state.servers.indices {
                let shouldBePreferred = index == existingIndex
                if state.servers[index].isPreferred != shouldBePreferred {
                    state.servers[index].isPreferred = shouldBePreferred
                    didChange = true
                }
            }
        } else {
            for index in state.servers.indices where state.servers[index].isPreferred {
                state.servers[index].isPreferred = false
                didChange = true
            }
            state.servers.append(
                CoreServer(
                    endpoint: endpoint,
                    status: endpoint == activeServerEndpoint ? .connected : .available,
                    isPreferred: true
                )
            )
            didChange = true
        }

        guard didChange else {
            return
        }

        do {
            try persistServers()
            recordNetworkUpdateLocked()
        } catch {
            emitNetworkLog("eD2k preferred server persistence failed: \(error.localizedDescription)")
        }
    }

    private func updateServerStatusesLocked(connectedEndpoint: ED2KServerEndpoint?) {
        activeServerEndpoint = connectedEndpoint

        guard state.servers.isEmpty == false else {
            return
        }

        var didChange = false
        for index in state.servers.indices {
            let previous = state.servers[index].status
            if let connectedEndpoint, state.servers[index].endpoint == connectedEndpoint {
                state.servers[index].status = .connected
            } else if previous == .connected {
                state.servers[index].status = .available
            }

            didChange = didChange || previous != state.servers[index].status
        }

        guard didChange else {
            return
        }

        do {
            try persistServers()
            recordNetworkUpdateLocked()
        } catch {
            emitNetworkLog("eD2k server status persistence failed: \(error.localizedDescription)")
        }
    }

    private func markServerUnavailableLocked(_ endpoint: ED2KServerEndpoint) {
        if let index = state.servers.firstIndex(where: { $0.endpoint == endpoint }) {
            state.servers[index].status = .unavailable
            state.servers[index].isPreferred = false
        }
    }

    private func importServersLocked(_ endpoints: [ED2KServerEndpoint]) throws -> Bool {
        guard endpoints.isEmpty == false else {
            return false
        }

        var didChange = false
        var hasPreferredServer = state.servers.contains(where: \.isPreferred)
        for endpoint in endpoints {
            if let index = state.servers.firstIndex(where: { $0.endpoint == endpoint }) {
                let desiredStatus: CoreServerStatus = endpoint == activeServerEndpoint ? .connected : .available
                if state.servers[index].status != desiredStatus {
                    state.servers[index].status = desiredStatus
                    didChange = true
                }
                continue
            }

            state.servers.append(
                CoreServer(
                    endpoint: endpoint,
                    status: endpoint == activeServerEndpoint ? .connected : .available,
                    isPreferred: hasPreferredServer == false
                )
            )
            hasPreferredServer = true
            didChange = true
        }

        guard didChange else {
            return false
        }

        try persistServers()
        return true
    }

    private func persist(_ transfer: CoreTransfer) throws {
        do {
            try transferStore?.upsert(transfer)
        } catch {
            throw CoreServiceError.persistence(error.localizedDescription)
        }
    }

    private func removePersistedTransfer(_ transfer: CoreTransfer) throws {
        do {
            try transferStore?.remove(transfer)
        } catch {
            throw CoreServiceError.persistence(error.localizedDescription)
        }
    }

    private func persistServers() throws {
        do {
            try transferStore?.saveServers(state.servers)
        } catch {
            throw CoreServiceError.persistence(error.localizedDescription)
        }
    }

    private func persistResumeCheckpointLocked() {
        guard let transferStore else {
            return
        }

        let activeTransferIDs = state.transfers.compactMap { transfer -> UUID? in
            switch transfer.status {
            case .queued, .downloading, .verifying:
                return transfer.id
            case .paused, .completed, .failed:
                return nil
            }
        }

        let checkpoint = CoreResumeCheckpoint(
            activeTransferIDs: activeTransferIDs,
            activeSearchQuery: activeSearchQuery,
            serverConfiguration: reconnectConfiguration.map(CoreResumeServerConfiguration.init(sessionConfiguration:))
        )

        do {
            try transferStore.saveResumeCheckpoint(checkpoint)
        } catch {
            emitNetworkLog("eD2k resume checkpoint persistence failed: \(error.localizedDescription)")
        }
    }

    private static func normalizedPersistedSnapshot(_ snapshot: CoreSnapshot) -> CoreSnapshot {
        var snapshot = snapshot
        if snapshot.servers.filter(\.isPreferred).count > 1 {
            var didKeepPreferred = false
            snapshot.servers = snapshot.servers.map { server in
                var server = server
                if server.isPreferred {
                    if didKeepPreferred {
                        server.isPreferred = false
                    } else {
                        didKeepPreferred = true
                    }
                }
                return server
            }
        }
        if snapshot.network.isConnected == false {
            snapshot.servers = snapshot.servers.map { server in
                var server = server
                if server.status == .connected {
                    server.status = .available
                }
                return server
            }
        }
        return snapshot
    }

    private static func normalizedCrashRecoveredSnapshot(
        _ snapshot: CoreSnapshot,
        checkpoint: CoreResumeCheckpoint?
    ) -> CoreSnapshot {
        var snapshot = snapshot
        let activeTransferIDs = Set(
            checkpoint?.activeTransferIDs
                ?? snapshot.transfers.compactMap { transfer in
                    switch transfer.status {
                    case .downloading, .verifying:
                        return transfer.id
                    case .queued, .paused, .completed, .failed:
                        return nil
                    }
                }
        )

        snapshot.transfers = snapshot.transfers.map { transfer in
            var transfer = transfer
            guard activeTransferIDs.contains(transfer.id) else {
                return transfer
            }
            if transfer.status == .downloading || transfer.status == .verifying {
                transfer.status = .queued
            }
            transfer.downloadSpeedBytesPerSecond = 0
            transfer.uploadSpeedBytesPerSecond = 0
            transfer.sources = 0
            transfer.availability = 0
            return transfer
        }
        return snapshot
    }

    private func restorePersistedPeerSourceState() {
        guard let transferStore else {
            return
        }

        withLock {
            for transfer in state.transfers {
                guard let record = try? transferStore.loadRecord(for: transfer.id),
                      record.peerSourceBookmarks.isEmpty == false else {
                    continue
                }

                peerSourceQueues[transfer.id] = record.peerSourceBookmarks.map(\.endpoint)
                peerSourceFailures[transfer.id] = Dictionary(
                    uniqueKeysWithValues: record.peerSourceBookmarks.map { bookmark in
                        (bookmark.endpoint, max(0, bookmark.failureCount))
                    }
                )
                peerSourceCooldowns[transfer.id] = Dictionary(
                    uniqueKeysWithValues: record.peerSourceBookmarks.compactMap { bookmark in
                        guard let cooldownUntil = bookmark.cooldownUntil,
                              cooldownUntil > Date() else {
                            return nil
                        }
                        return (bookmark.endpoint, cooldownUntil)
                    }
                )
                let validInflightBookmarks = record.peerInflightBookmarks.filter { bookmark in
                    Date().timeIntervalSince(bookmark.reservedAt) < Self.peerInflightReservationTTL
                }
                if validInflightBookmarks.isEmpty == false {
                    peerInflightRanges[transfer.id] = Dictionary(
                        uniqueKeysWithValues: validInflightBookmarks.map { bookmark in
                            (
                                bookmark.endpoint,
                                ED2KPartRange(
                                    startOffset: bookmark.startOffset,
                                    endOffset: bookmark.endOffset
                                )
                            )
                        }
                    )
                    peerInflightRangeTimestamps[transfer.id] = Dictionary(
                        uniqueKeysWithValues: validInflightBookmarks.map { bookmark in
                            (bookmark.endpoint, bookmark.reservedAt)
                        }
                    )
                }
                peerChunkRetryStates[transfer.id] = Dictionary(
                    uniqueKeysWithValues: record.peerChunkRetryBookmarks.map { bookmark in
                        (
                            PeerChunkRetryKey(
                                range: ED2KPartRange(
                                    startOffset: bookmark.startOffset,
                                    endOffset: bookmark.endOffset
                                )
                            ),
                            PeerChunkRetryState(
                                failureCount: max(0, bookmark.failureCount),
                                cooldownUntil: bookmark.cooldownUntil,
                                lastFailureAt: bookmark.lastFailureAt
                            )
                        )
                    }
                )
                pruneExpiredPeerSourceCooldownsLocked(for: transfer.id)
                pruneExpiredPeerChunkRetryCooldownsLocked(for: transfer.id)
                reorderPeerSourceQueueLocked(for: transfer.id)
            }
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func checkDiskSpace(for size: UInt64) -> Bool {
        let tempURL: URL
        if let store = transferStore {
            tempURL = store.tempDirectory
        } else {
            tempURL = FileManager.default.temporaryDirectory
        }
        do {
            let values = try tempURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                let freeMB = available / 1_000_000
                let neededMB = Int64(size) / 1_000_000 + 200 // 200 MB margin
                if freeMB < neededMB {
                    emitNetworkLog("Disco insuficiente: \(freeMB) MB libres, \(neededMB) MB necesitados")
                    return false
                }
            }
        } catch {
            // Can't determine disk space — proceed anyway
        }
        return true
    }

    private static func loadOrCreateClientUserHash(transferStore: CoreTransferStore?) -> Data {
        if let transferStore,
           let storedIdentity = try? transferStore.loadClientIdentity(),
           storedIdentity.userHash.count == 16 {
            let normalizedHash = normalizedClientUserHash(storedIdentity.userHash)
            if normalizedHash != storedIdentity.userHash {
                try? transferStore.saveClientIdentity(CoreClientIdentity(userHash: normalizedHash))
            }
            return normalizedHash
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        let generatedHash = normalizedClientUserHash(Data(bytes))

        if let transferStore {
            try? transferStore.saveClientIdentity(CoreClientIdentity(userHash: generatedHash))
        }

        return generatedHash
    }

    private static func normalizedClientUserHash(_ hash: Data) -> Data {
        guard hash.count == 16 else { return hash }
        var bytes = Array(hash)
        bytes[5] = 0x0E
        bytes[14] = 0x6F
        return Data(bytes)
    }

    private static func normalizedServerSessionConfiguration(
        _ configuration: ED2KServerSessionConfiguration
    ) -> ED2KServerSessionConfiguration {
        ED2KServerSessionConfiguration(
            endpoint: configuration.endpoint,
            userHash: normalizedClientUserHash(configuration.userHash),
            clientID: configuration.clientID,
            tcpPort: configuration.tcpPort,
            nickname: configuration.nickname,
            protocolVersion: max(
                configuration.protocolVersion,
                ED2KLoginRequest.defaultProtocolVersion
            ),
            flags: normalizedServerCapabilityFlags(configuration.flags)
        )
    }

    private static func normalizedServerCapabilityFlags(_ flags: UInt32) -> UInt32 {
        if flags == 0
            || flags == 1
            || flags == ED2KLoginRequest.legacyDefaultServerCapabilityFlags {
            return ED2KLoginRequest.defaultServerCapabilityFlags
        }

        return flags
    }
}

private extension CoreSearchResult {
    init(ed2kSearchResult: ED2KSearchResult, network: String) {
        self.init(
            fileName: ed2kSearchResult.stringTag(named: ED2KSearchTagName.fileName) ?? ed2kSearchResult.fileHash.hexadecimalString,
            sizeInBytes: ed2kSearchResult.integerTag(named: ED2KSearchTagName.fileSize) ?? 0,
            sources: Int(ed2kSearchResult.integerTag(named: ED2KSearchTagName.sources) ?? (ed2kSearchResult.clientID == 0 ? 0 : 1)),
            availability: Int(ed2kSearchResult.integerTag(named: ED2KSearchTagName.completeSources) ?? (ed2kSearchResult.clientPort == 0 ? 0 : 1)),
            network: network,
            ed2kHash: ed2kSearchResult.fileHash.hexadecimalString,
            sourceClientID: ed2kSearchResult.clientID == 0 ? nil : ed2kSearchResult.clientID,
            sourceClientPort: ed2kSearchResult.clientPort == 0 ? nil : ed2kSearchResult.clientPort
        )
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    init?(hexadecimalString: String) {
        guard hexadecimalString.count == 32 else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexadecimalString.count / 2)

        var index = hexadecimalString.startIndex
        while index < hexadecimalString.endIndex {
            let nextIndex = hexadecimalString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimalString[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }
}
