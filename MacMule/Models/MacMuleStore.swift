import AppKit
import Combine
import Foundation
import MacMuleCore

@MainActor
final class MacMuleStore: ObservableObject {
    // MARK: - UI state
    @Published var selectedSection: MacMuleSection? = .dashboard
    @Published var selectedDownloadID: TransferItem.ID?
    @Published var searchQuery = ""
    @Published var searchMethod: SearchMethod = .server
    @Published var searchFileKind: FileKind? = nil
    @Published var searchMinSizeKB: String = ""
    @Published var searchMaxSizeKB: String = ""
    @Published var searchExtensionFilter: String = ""
    @Published var ed2kLinkText = ""
    @Published private(set) var isSearching = false
    @Published var downloadSortOrder: DownloadSortOrder = .dateAdded
    @Published private(set) var isAddingED2KLink = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRestartingCore = false
    @Published private(set) var ed2kLinkError: String?

    // MARK: - Settings (UserDefaults-backed)
    @Published var downloadDirectory: String {
        didSet {
            UserDefaults.standard.set(downloadDirectory, forKey: "downloadDirectory")
            applyDirectoryConfigIfNeeded()
        }
    }
    @Published var tempDirectory: String {
        didSet {
            UserDefaults.standard.set(tempDirectory, forKey: "tempDirectory")
            applyDirectoryConfigIfNeeded()
        }
    }
    @Published var maxDownloadKilobytes: Double {
        didSet {
            UserDefaults.standard.set(maxDownloadKilobytes, forKey: "maxDownloadKilobytes")
            applyBandwidthConfig()
        }
    }
    @Published var maxUploadKilobytes: Double {
        didSet {
            UserDefaults.standard.set(maxUploadKilobytes, forKey: "maxUploadKilobytes")
            applyBandwidthConfig()
        }
    }
    @Published var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "autoConnect") }
    }
    @Published var shareCompletedDownloads: Bool {
        didSet { UserDefaults.standard.set(shareCompletedDownloads, forKey: "shareCompletedDownloads") }
    }
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: "nickname") }
    }
    @Published var tcpPort: String {
        didSet { UserDefaults.standard.set(tcpPort, forKey: "tcpPort") }
    }
    @Published var udpPort: String {
        didSet { UserDefaults.standard.set(udpPort, forKey: "udpPort") }
    }
    @Published var maxConnections: String {
        didSet { UserDefaults.standard.set(maxConnections, forKey: "maxConnections") }
    }
    @Published var maxSourcesPerFile: String {
        didSet { UserDefaults.standard.set(maxSourcesPerFile, forKey: "maxSourcesPerFile") }
    }
    @Published var enableKad: Bool {
        didSet { UserDefaults.standard.set(enableKad, forKey: "enableKad") }
    }
    @Published var enableUPnP: Bool {
        didSet { UserDefaults.standard.set(enableUPnP, forKey: "enableUPnP") }
    }
    @Published var autoRemoveCompleted: Bool {
        didSet { UserDefaults.standard.set(autoRemoveCompleted, forKey: "autoRemoveCompleted") }
    }
    @Published var obfuscationEnabled: Bool {
        didSet { UserDefaults.standard.set(obfuscationEnabled, forKey: "obfuscationEnabled") }
    }
    @Published var secureIdentEnabled: Bool {
        didSet { UserDefaults.standard.set(secureIdentEnabled, forKey: "secureIdentEnabled") }
    }

    // MARK: - Core data
    @Published private(set) var downloads: [TransferItem]
    @Published private(set) var uploads: [TransferItem]
    @Published private(set) var searchResults: [SearchResult]
    @Published private(set) var servers: [ServerSnapshot]
    @Published private(set) var sharedFiles: [SharedFile]
    @Published private(set) var statistics: [StatMetric]
    @Published private(set) var network: NetworkSummary
    @Published private(set) var kad: KadSummary
    @Published private(set) var kadNodes: [KadNode]
    @Published private(set) var kadBucketStats: [KadBucketStat]
    @Published private(set) var kadActiveSearches: [KadSearchSummary]
    @Published private(set) var transferPeers: [UUID: [SourceDetail]]
    @Published private(set) var categories: [CategoryItem]
    @Published var schedulerEnabled: Bool = false
    @Published var scheduleEntries: [ScheduleEntryItem] = []
    @Published private(set) var coreRuntimeStatus: MacMuleCoreRuntimeStatus
    @Published private(set) var coreRuntimeLogs: [MacMuleCoreLogEntry]
    @Published var kadBootstrapHost: String = ""
    @Published var kadBootstrapPort: String = "4662"

    // MARK: - Speed chart history (last 60 samples, normalized 0-1)
    @Published private(set) var downloadSpeedHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var uploadSpeedHistory: [Double] = Array(repeating: 0, count: 60)

    // MARK: - Session
    private let sessionStartDate = Date()
    @Published private(set) var sessionDurationText: String = "0 s"

    private var core: any MacMuleCoreClient
    private var didStart = false
    private var lastCoreEventSequence: UInt64 = 0
    private var eventPollingTask: Task<Void, Never>?
    private var sessionTimerTask: Task<Void, Never>?

    // Soft caps for chart normalization (bytes/s)
    private static let chartDownloadCap: Double = 10_000_000   // 10 MB/s
    private static let chartUploadCap: Double = 5_000_000      // 5 MB/s

    init(core: (any MacMuleCoreClient)? = nil) {
        // Fast, non-blocking init — real daemon is launched async in start()
        self.core = core ?? MacMuleCoreClientFactory.makeDefaultClient()
        coreRuntimeStatus = self.core.runtimeStatus
        coreRuntimeLogs = self.core.runtimeLogs

        downloadDirectory = UserDefaults.standard.string(forKey: "downloadDirectory") ?? "~/Downloads/MacMule"
        tempDirectory = UserDefaults.standard.string(forKey: "tempDirectory")
            ?? "~/Library/Application Support/MacMule/Core/Temp"
        maxDownloadKilobytes = UserDefaults.standard.double(forKey: "maxDownloadKilobytes").nonZero ?? 4096
        maxUploadKilobytes = UserDefaults.standard.double(forKey: "maxUploadKilobytes").nonZero ?? 512
        autoConnect = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true
        shareCompletedDownloads = UserDefaults.standard.bool(forKey: "shareCompletedDownloads")
        nickname = UserDefaults.standard.string(forKey: "nickname") ?? "MacMule"
        tcpPort = UserDefaults.standard.string(forKey: "tcpPort") ?? "4662"
        udpPort = UserDefaults.standard.string(forKey: "udpPort") ?? "4672"
        maxConnections = UserDefaults.standard.string(forKey: "maxConnections") ?? "500"
        maxSourcesPerFile = UserDefaults.standard.string(forKey: "maxSourcesPerFile") ?? "50"
        enableKad = UserDefaults.standard.object(forKey: "enableKad") as? Bool ?? true
        enableUPnP = UserDefaults.standard.object(forKey: "enableUPnP") as? Bool ?? true
        autoRemoveCompleted = UserDefaults.standard.bool(forKey: "autoRemoveCompleted")
        obfuscationEnabled = UserDefaults.standard.bool(forKey: "obfuscationEnabled")
        secureIdentEnabled = UserDefaults.standard.bool(forKey: "secureIdentEnabled")

        let snapshot = MacMuleSnapshot.empty
        downloads = snapshot.downloads
        uploads = snapshot.uploads
        searchResults = snapshot.searchResults
        servers = snapshot.servers
        sharedFiles = snapshot.sharedFiles
        statistics = snapshot.statistics
        network = snapshot.network
        kad = KadSummary(isRunning: false, isConnected: false, isFirewalled: true, nodeCount: 0, activeSearchCount: 0, totalKeywords: 0, totalSources: 0)
        kadNodes = []
        kadBucketStats = []
        kadActiveSearches = []
        transferPeers = [:]
        categories = []
    }

    // MARK: - Computed properties

    var selectedDownload: TransferItem? {
        guard let selectedDownloadID else { return downloads.first }
        return downloads.first { $0.id == selectedDownloadID }
    }

    var totalDownloadSpeed: Int64 {
        let measuredQueueSpeed = network.downloadSpeedBytesPerSecond
        if measuredQueueSpeed > 0 || downloads.contains(where: { $0.status == .downloading }) {
            return measuredQueueSpeed
        }
        return downloads.reduce(0) { $0 + $1.downloadSpeedBytesPerSecond }
    }

    var totalUploadSpeed: Int64 {
        uploads.reduce(0) { $0 + $1.uploadSpeedBytesPerSecond }
    }

    var totalSources: Int {
        downloads.reduce(0) { $0 + $1.sources }
    }

    var canRestartCore: Bool {
        core.canRestartCore
    }

    var activeDownloadCount: Int {
        downloads.filter { $0.status == .downloading }.count
    }

    var pausedDownloadCount: Int {
        downloads.filter { $0.status == .paused }.count
    }

    var completedDownloadCount: Int {
        downloads.filter { $0.status == .completed }.count
    }

    /// The root directory used by the daemon for metadata, identity, and servers.
    var coreStorageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("MacMule", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
    }

    var coreIncomingDirectoryURL: URL {
        resolvedDownloadDirectoryURL
    }

    var coreTempDirectoryURL: URL {
        resolvedTempDirectoryURL
    }

    // MARK: - Lifecycle

    func start() async {
        guard didStart == false else { return }
        didStart = true

        // Launch real daemon — replaces the empty placeholder
        if let realCore = await MacMuleCoreClientFactory.makeRealClientAsync(
            storageDirectory: coreStorageDirectoryURL,
            incomingDirectory: resolvedDownloadDirectoryURL,
            tempDirectory: resolvedTempDirectoryURL
        ) {
            core = realCore
        }
        updateCoreRuntimeStatus()

        await refreshSnapshot()
        startEventPolling()
        startSessionTimer()

        // Keep at least a small fallback pool so one dead/rejecting server does not trap connection.
        if servers.count < 2 {
            await bootstrapKnownServers()
        }

        if autoConnect && network.isConnected == false {
            toggleConnection()
        }
    }

    /// Seeds a handful of known public eD2k servers so the user can connect
    /// immediately and the core has failover options.
    private func bootstrapKnownServers() async {
        for defaultServer in CoreDefaultED2KServers.bundled {
            let s = defaultServer.endpoint
            _ = await core.addServer(host: s.host, port: s.port)
        }
        // One snapshot refresh is enough to show all new servers at once
        let snapshot = await core.currentSnapshot()
        apply(snapshot)
    }

    func refreshSnapshot() async {
        isRefreshing = true
        let snapshot = await core.currentSnapshot()
        updateCoreRuntimeStatus()
        apply(snapshot)
        isRefreshing = false
    }

    private func startEventPolling() {
        guard eventPollingTask == nil else { return }

        eventPollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                // Poll faster when there are active downloads
                let hasActive = (self?.activeDownloadCount ?? 0) > 0
                let interval: UInt64 = hasActive ? 500_000_000 : 2_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                await self?.pollCoreEvents()
                await self?.sampleSpeed()
            }
        }
    }

    private func startSessionTimer() {
        sessionTimerTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.updateSessionDuration()
            }
        }
    }

    private func updateSessionDuration() {
        let elapsed = Int(Date().timeIntervalSince(sessionStartDate))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            sessionDurationText = "\(hours) h \(minutes) m"
        } else if minutes > 0 {
            sessionDurationText = "\(minutes) m \(seconds) s"
        } else {
            sessionDurationText = "\(seconds) s"
        }
    }

    private func pollCoreEvents() async {
        let batch = await core.events(after: lastCoreEventSequence)
        updateCoreRuntimeStatus()
        guard batch.latestSequence > lastCoreEventSequence else {
            if shouldRefreshTransferSpeeds(from: batch.snapshot) {
                apply(batch.snapshot)
            }
            return
        }

        lastCoreEventSequence = batch.latestSequence
        apply(batch.snapshot)
    }

    private func shouldRefreshTransferSpeeds(from snapshot: MacMuleSnapshot) -> Bool {
        let hasLiveTransfer = snapshot.downloads.contains { transfer in
            transfer.status == .downloading || transfer.downloadSpeedBytesPerSecond > 0
        }
        let currentlyShowsSpeed = downloads.contains { $0.downloadSpeedBytesPerSecond > 0 }
        return hasLiveTransfer || currentlyShowsSpeed
    }

    private func sampleSpeed() {
        let dl = min(Double(totalDownloadSpeed) / Self.chartDownloadCap, 1.0)
        let ul = min(Double(totalUploadSpeed) / Self.chartUploadCap, 1.0)

        var newDL = downloadSpeedHistory
        newDL.removeFirst()
        newDL.append(dl)
        downloadSpeedHistory = newDL

        var newUL = uploadSpeedHistory
        newUL.removeFirst()
        newUL.append(ul)
        uploadSpeedHistory = newUL
    }

    // MARK: - Actions

    func toggleConnection() {
        let shouldConnect = network.isConnected == false

        Task {
            let snapshot = await core.setConnection(enabled: shouldConnect)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            isSearching = false
            return
        }

        Task {
            isSearching = true
            let snapshot: MacMuleSnapshot
            if searchMethod == .kad {
                snapshot = await core.kadSearchKeyword(query: query)
            } else {
                snapshot = await core.search(query: query)
            }
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func addDownload(from result: SearchResult) {
        Task {
            let previousIDs = Set(downloads.map(\.id))
            let snapshot = await core.addDownload(from: result)
            updateCoreRuntimeStatus()
            apply(snapshot)

            if let newDownload = downloads.first(where: { previousIDs.contains($0.id) == false }) {
                selectedDownloadID = newDownload.id
            } else {
                selectedDownloadID = downloads.first { $0.ed2kHash == result.ed2kHash }?.id
            }

            selectedSection = .downloads
        }
    }

    func addED2KLink() {
        let rawLink = ed2kLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawLink.isEmpty == false else {
            ed2kLinkError = "Pega un enlace ed2k:// primero."
            return
        }
        enqueueED2KLinkString(rawLink)
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "ed2k" else { return }
        enqueueED2KLinkString(url.absoluteString)
    }

    func pasteED2KLink() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("ed2k://") else { return }
        enqueueED2KLinkString(trimmed)
    }

    private func enqueueED2KLinkString(_ rawLink: String) {
        let link: ED2KFileLink
        do {
            link = try ED2KLinkParser.parseFileLink(rawLink)
        } catch {
            ed2kLinkError = "Invalid eD2k link: \(error.localizedDescription)"
            return
        }

        Task {
            isAddingED2KLink = true
            ed2kLinkError = nil
            let snapshot = await core.addED2KLink(link)
            updateCoreRuntimeStatus()
            apply(snapshot)
            selectedDownloadID = downloads.first { $0.ed2kHash == link.hash }?.id
            selectedSection = .downloads
            ed2kLinkText = ""
            isAddingED2KLink = false
        }
    }

    func togglePause(downloadID: TransferItem.ID) {
        guard let download = downloads.first(where: { $0.id == downloadID }) else { return }
        let shouldPause = download.status != .paused

        Task {
            let snapshot = await core.setDownloadPaused(id: downloadID, paused: shouldPause)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func retryDownload(downloadID: TransferItem.ID) {
        Task {
            let snapshot = await core.setDownloadPaused(id: downloadID, paused: false)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func removeDownload(downloadID: TransferItem.ID) {
        Task {
            let snapshot = await core.removeDownload(id: downloadID)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func addServer(host: String, port: String) {
        guard let portNum = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }

        Task {
            let snapshot = await core.addServer(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: portNum)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func connect(to server: ServerSnapshot) {
        guard let endpoint = parseServerEndpoint(server.address) else { return }

        Task {
            let snapshot = await core.connectToServer(host: endpoint.host, port: endpoint.port)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func connectToBestServer() {
        if let connected = servers.first(where: { $0.health == .connected }) {
            connect(to: connected)
            return
        }

        guard let server = servers
            .filter({ $0.health != .unavailable })
            .sorted(by: { lhs, rhs in
                if lhs.isPreferred != rhs.isPreferred {
                    return lhs.isPreferred
                }
                if lhs.pingMilliseconds != rhs.pingMilliseconds {
                    return lhs.pingMilliseconds < rhs.pingMilliseconds
                }
                return lhs.users > rhs.users
            })
            .first ?? servers.first else {
            toggleConnection()
            return
        }

        connect(to: server)
    }

    func remove(server: ServerSnapshot) {
        guard let endpoint = parseServerEndpoint(server.address) else { return }

        Task {
            let snapshot = await core.removeServer(host: endpoint.host, port: endpoint.port)
            updateCoreRuntimeStatus()
            apply(snapshot)
        }
    }

    func pauseAllDownloads() {
        Task {
            var latest = await core.currentSnapshot()
            for download in downloads where download.status != .paused && download.status != .completed && download.status != .failed {
                latest = await core.setDownloadPaused(id: download.id, paused: true)
            }
            updateCoreRuntimeStatus()
            apply(latest)
        }
    }

    func resumeAllDownloads() {
        Task {
            var latest = await core.currentSnapshot()
            for download in downloads where download.status == .paused {
                latest = await core.setDownloadPaused(id: download.id, paused: false)
            }
            updateCoreRuntimeStatus()
            apply(latest)
        }
    }

    func removeCompletedDownloads() {
        removeDownloads(matching: { $0.status == .completed })
    }

    func removeFailedDownloads() {
        removeDownloads(matching: { $0.status == .failed })
    }

    private func removeDownloads(matching shouldRemove: @escaping @MainActor (TransferItem) -> Bool) {
        Task {
            var latest = await core.currentSnapshot()
            for download in downloads where shouldRemove(download) {
                latest = await core.removeDownload(id: download.id)
            }
            updateCoreRuntimeStatus()
            apply(latest)
        }
    }

    // MARK: - Server list update from URL

    @Published private(set) var isFetchingServerList = false
    @Published private(set) var serverListFetchError: String?

    func fetchServerList(from urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let url = URL(string: trimmed) else {
            serverListFetchError = "Invalid URL."
            return
        }
        Task {
            isFetchingServerList = true
            serverListFetchError = nil
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard httpCode == 200 else {
                    serverListFetchError = "HTTP error \(httpCode)."
                    isFetchingServerList = false
                    return
                }
                let servers = ServerMetParser.parse(data)
                guard servers.isEmpty == false else {
                    serverListFetchError = "No servers were found in the response."
                    isFetchingServerList = false
                    return
                }
                let snapshot = await core.importServers(servers: servers)
                updateCoreRuntimeStatus()
                apply(snapshot)
                serverListFetchError = nil
            } catch {
                serverListFetchError = error.localizedDescription
            }
            isFetchingServerList = false
        }
    }

    func resetServers() {
        Task {
            // Remove all current servers
            for server in servers {
                _ = await core.removeServer(host: parseServerEndpoint(server.address)?.host ?? "", port: parseServerEndpoint(server.address)?.port ?? 0)
            }
            // Re-bootstrap from defaults
            await bootstrapKnownServers()
            let snapshot = await core.currentSnapshot()
            apply(snapshot)
        }
    }

    func restartCore() {
        guard canRestartCore, isRestartingCore == false else { return }

        Task {
            isRestartingCore = true
            let snapshot = await core.restartCore()
            lastCoreEventSequence = 0
            updateCoreRuntimeStatus()
            apply(snapshot)
            isRestartingCore = false
        }
    }

    func kadStart() {
        Task {
            let snapshot = await core.kadStart()
            apply(snapshot)
        }
    }

    func kadStop() {
        Task {
            let snapshot = await core.kadStop()
            apply(snapshot)
        }
    }

    func kadBootstrap() {
        let host = kadBootstrapHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false, let port = UInt16(kadBootstrapPort.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

        Task {
            let snapshot = await core.kadBootstrap(host: host, port: port)
            apply(snapshot)
        }
    }

    func kadSearchKeyword(_ query: String) {
        Task {
            let snapshot = await core.kadSearchKeyword(query: query)
            apply(snapshot)
        }
    }

    func kadSearchSources(hash: String) {
        Task {
            let snapshot = await core.kadSearchSources(hash: hash)
            apply(snapshot)
        }
    }

    func addCategory(title: String, color: String) {
        Task {
            let snapshot = await core.addCategory(title: title, color: color)
            apply(snapshot)
        }
    }

    func removeCategory(id: UUID) {
        Task {
            let snapshot = await core.removeCategory(id: id)
            apply(snapshot)
        }
    }

    // MARK: - Scheduler

    func schedulerEnable(_ enabled: Bool) {
        schedulerEnabled = enabled
        Task {
            let snapshot = await core.schedulerEnable(enabled: enabled)
            apply(snapshot)
        }
    }

    func schedulerAddEntry(title: String, days: Set<Int>, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, actions: [String]) {
        let entry = ScheduleEntry(
            title: title,
            days: days,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            actions: actions.map { ScheduleAction(type: ScheduleActionType(rawValue: $0) ?? .setUploadLimit) }
        )
        scheduleEntries.append(ScheduleEntryItem(entry))
        Task {
            let snapshot = await core.schedulerAddEntry(title: title, days: days, startHour: startHour, startMinute: startMinute, endHour: endHour, endMinute: endMinute, actions: actions)
            apply(snapshot)
        }
    }

    func schedulerRemoveEntry(id: UUID) {
        scheduleEntries.removeAll { $0.id == id }
        Task {
            let snapshot = await core.schedulerRemoveEntry(id: id)
            apply(snapshot)
        }
    }

    // MARK: - Private helpers

    private func applyBandwidthConfig() {
        Task {
            let snapshot = await core.setConfig(
                maxDownloadKilobytes: Int(maxDownloadKilobytes),
                maxUploadKilobytes: Int(maxUploadKilobytes)
            )
            apply(snapshot)
        }
    }

    private func applyDirectoryConfigIfNeeded() {
        guard didStart, canRestartCore, isRestartingCore == false else { return }

        Task {
            isRestartingCore = true
            let snapshot = await core.restartCore()
            lastCoreEventSequence = 0
            updateCoreRuntimeStatus()
            apply(snapshot)
            isRestartingCore = false
        }
    }

    private func updateCoreRuntimeStatus() {
        coreRuntimeStatus = core.runtimeStatus
        coreRuntimeLogs = core.runtimeLogs
    }

    private func apply(_ snapshot: MacMuleSnapshot) {
        downloads = snapshot.downloads
        uploads = snapshot.uploads
        searchResults = snapshot.searchResults
        servers = snapshot.servers
        sharedFiles = snapshot.sharedFiles
        network = snapshot.network
        kad = KadSummary(
            isRunning: snapshot.kad.isRunning,
            isConnected: snapshot.kad.isConnected,
            isFirewalled: snapshot.kad.isFirewalled,
            nodeCount: snapshot.kad.nodeCount,
            activeSearchCount: snapshot.kad.activeSearchCount,
            totalKeywords: snapshot.kad.totalKeywords,
            totalSources: snapshot.kad.totalSources
        )
        kadNodes = snapshot.kad.nodes
        kadBucketStats = snapshot.kad.bucketStats
        kadActiveSearches = snapshot.kad.activeSearches
        transferPeers = snapshot.transferPeers
        categories = snapshot.categories
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStatus = snapshot.network.statusText.lowercased()
        isSearching =
            normalizedQuery.isEmpty == false &&
            (
                normalizedStatus.hasPrefix("conectando a ") ||
                normalizedStatus.hasPrefix("esperando conexion a ") ||
                normalizedStatus.hasPrefix("login enviado a ") ||
                normalizedStatus.hasPrefix("buscando:")
            )

        // Rebuild statistics with live session duration
        statistics = snapshot.statistics.map { metric in
            if metric.title == "Sesion" || metric.title == "Session" {
                return StatMetric(title: "Session", value: sessionDurationText, systemImage: metric.systemImage)
            }
            return metric
        }

        if let selectedDownloadID, downloads.contains(where: { $0.id == selectedDownloadID }) {
            return
        }

        selectedDownloadID = downloads.first?.id
    }

    private func parseServerEndpoint(_ address: String) -> (host: String, port: UInt16)? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(of: ":") else { return nil }

        let host = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard host.isEmpty == false, let port = UInt16(portText) else { return nil }
        return (host, port)
    }

    private var resolvedDownloadDirectoryURL: URL {
        let rawPath = NSString(string: downloadDirectory).expandingTildeInPath
        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }

    private var resolvedTempDirectoryURL: URL {
        let rawPath = NSString(string: tempDirectory).expandingTildeInPath
        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }
}

// MARK: - Helpers

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
