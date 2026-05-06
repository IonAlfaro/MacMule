import Foundation
import MacMuleCore

struct MacMuleSnapshot: Hashable {
    var downloads: [TransferItem]
    var uploads: [TransferItem]
    var searchResults: [SearchResult]
    var servers: [ServerSnapshot]
    var sharedFiles: [SharedFile]
    var statistics: [StatMetric]
    var network: NetworkSummary
    var kad: KadState
    var transferPeers: [UUID: [SourceDetail]]
    var categories: [CategoryItem]

    struct KadState: Hashable {
        var isRunning: Bool
        var isConnected: Bool
        var isFirewalled: Bool
        var nodeCount: Int
        var activeSearchCount: Int
        var totalKeywords: Int
        var totalSources: Int
        var nodes: [KadNode]
        var bucketStats: [KadBucketStat]
        var activeSearches: [KadSearchSummary]
    }

    static let empty = MacMuleSnapshot(
        downloads: [],
        uploads: [],
        searchResults: [],
        servers: [],
        sharedFiles: [],
        statistics: [],
        network: NetworkSummary(
            isConnected: false,
            statusText: "Offline",
            highID: false,
            kadNodes: 0,
            tcpPort: 4662,
            udpPort: 4672
        ),
        kad: KadState(
            isRunning: false,
            isConnected: false,
            isFirewalled: true,
            nodeCount: 0,
            activeSearchCount: 0,
            totalKeywords: 0,
            totalSources: 0,
            nodes: [],
            bucketStats: [],
            activeSearches: []
        ),
        transferPeers: [:],
        categories: []
    )
}

struct CategoryItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var color: String
}

struct ScheduleEntryItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var dayNames: [String]
    var formattedTime: String
    var enabled: Bool
}

extension ScheduleEntryItem {
    init(_ entry: ScheduleEntry) {
        self.id = entry.id
        self.title = entry.title
        self.dayNames = entry.dayNames
        self.formattedTime = entry.formattedTime
        self.enabled = entry.enabled
    }
}

enum MacMuleCoreEvent: Hashable {
    case snapshotChanged
    case downloadAdded(UUID)
    case downloadUpdated(UUID)
    case downloadRemoved(UUID)
    case connectionChanged(Bool)
}

struct MacMuleEventBatch: Hashable {
    var afterSequence: UInt64
    var latestSequence: UInt64
    var events: [MacMuleCoreEvent]
    var snapshot: MacMuleSnapshot

    static func empty(after sequence: UInt64, snapshot: MacMuleSnapshot = .empty) -> MacMuleEventBatch {
        MacMuleEventBatch(
            afterSequence: sequence,
            latestSequence: sequence,
            events: [],
            snapshot: snapshot
        )
    }
}

struct MacMuleCoreRuntimeStatus: Hashable {
    var title: String
    var detail: String
    var systemImage: String
    var isWarning: Bool

    static let demo = MacMuleCoreRuntimeStatus(
        title: "Local demo",
        detail: "In-memory core",
        systemImage: "shippingbox",
        isWarning: true
    )
}

enum MacMuleCoreLogLevel: String, Hashable {
    case info
    case warning
    case error

    var title: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

struct MacMuleCoreLogEntry: Identifiable, Hashable {
    let id = UUID()
    var timestamp: Date
    var level: MacMuleCoreLogLevel
    var message: String
}

@MainActor
protocol MacMuleCoreClient {
    var runtimeStatus: MacMuleCoreRuntimeStatus { get }
    var runtimeLogs: [MacMuleCoreLogEntry] { get }
    var canRestartCore: Bool { get }

    func currentSnapshot() async -> MacMuleSnapshot
    func events(after sequence: UInt64) async -> MacMuleEventBatch
    func search(query: String) async -> MacMuleSnapshot
    func addDownload(from result: SearchResult) async -> MacMuleSnapshot
    func addED2KLink(_ link: ED2KFileLink) async -> MacMuleSnapshot
    func setDownloadPaused(id: TransferItem.ID, paused: Bool) async -> MacMuleSnapshot
    func removeDownload(id: TransferItem.ID) async -> MacMuleSnapshot
    func setConnection(enabled: Bool) async -> MacMuleSnapshot
    func connectToServer(host: String, port: UInt16) async -> MacMuleSnapshot
    func addServer(host: String, port: UInt16) async -> MacMuleSnapshot
    func removeServer(host: String, port: UInt16) async -> MacMuleSnapshot
    func importServers(servers: [(host: String, port: UInt16)]) async -> MacMuleSnapshot
    func setConfig(maxDownloadKilobytes: Int, maxUploadKilobytes: Int) async -> MacMuleSnapshot
    func restartCore() async -> MacMuleSnapshot
    func kadStart() async -> MacMuleSnapshot
    func kadStop() async -> MacMuleSnapshot
    func kadBootstrap(host: String, port: UInt16) async -> MacMuleSnapshot
    func kadSearchKeyword(query: String) async -> MacMuleSnapshot
    func kadSearchSources(hash: String) async -> MacMuleSnapshot
    func addCategory(title: String, color: String) async -> MacMuleSnapshot
    func removeCategory(id: UUID) async -> MacMuleSnapshot
    func schedulerEnable(enabled: Bool) async -> MacMuleSnapshot
    func schedulerAddEntry(title: String, days: Set<Int>, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, actions: [String]) async -> MacMuleSnapshot
    func schedulerRemoveEntry(id: UUID) async -> MacMuleSnapshot
}
