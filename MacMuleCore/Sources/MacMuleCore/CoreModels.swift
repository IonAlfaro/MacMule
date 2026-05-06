import Foundation

public enum CoreFileKind: String, Codable, Equatable, Sendable {
    case video
    case audio
    case archive
    case document
    case application
    case other

    public static func inferred(from fileName: String) -> CoreFileKind {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "avi", "m4v", "mkv", "mov", "mp4", "webm":
            return .video
        case "aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav":
            return .audio
        case "7z", "bz2", "dmg", "gz", "iso", "rar", "tar", "xz", "zip":
            return .archive
        case "doc", "docx", "epub", "md", "numbers", "pages", "pdf", "rtf", "txt", "xls", "xlsx":
            return .document
        case "app", "ipa", "pkg":
            return .application
        default:
            return .other
        }
    }
}

public enum CoreTransferStatus: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case paused
    case verifying
    case completed
    case failed
}

public enum CoreTransferPriority: Int, Codable, Equatable, Sendable, CaseIterable {
    case veryLow = 0
    case low = 1
    case normal = 2
    case high = 3
    case veryHigh = 4
    case auto = 5

    public var title: String {
        switch self {
        case .veryLow: "Very low"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .veryHigh: "Very high"
        case .auto: "Automatic"
        }
    }
}

public struct CoreTransfer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var fileName: String
    public var kind: CoreFileKind
    public var sizeInBytes: UInt64
    public var completedBytes: UInt64
    public var downloadSpeedBytesPerSecond: UInt64
    public var uploadSpeedBytesPerSecond: UInt64
    public var sources: Int
    public var availability: Int
    public var status: CoreTransferStatus
    public var downloadPriority: CoreTransferPriority
    public var ed2kHash: String
    public var rootHash: String?
    public var partHashes: [String]
    public var categoryID: UUID?

    public init(
        id: UUID = UUID(),
        fileName: String,
        kind: CoreFileKind,
        sizeInBytes: UInt64,
        completedBytes: UInt64 = 0,
        downloadSpeedBytesPerSecond: UInt64 = 0,
        uploadSpeedBytesPerSecond: UInt64 = 0,
        sources: Int = 0,
        availability: Int = 0,
        status: CoreTransferStatus = .queued,
        downloadPriority: CoreTransferPriority = .auto,
        ed2kHash: String,
        rootHash: String? = nil,
        partHashes: [String] = [],
        categoryID: UUID? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.sizeInBytes = sizeInBytes
        self.completedBytes = completedBytes
        self.downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond
        self.uploadSpeedBytesPerSecond = uploadSpeedBytesPerSecond
        self.sources = sources
        self.availability = availability
        self.status = status
        self.downloadPriority = downloadPriority
        self.ed2kHash = ed2kHash.uppercased()
        self.rootHash = rootHash?.uppercased()
        self.partHashes = partHashes.map { $0.uppercased() }
        self.categoryID = categoryID
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileName, kind, sizeInBytes, completedBytes
        case downloadSpeedBytesPerSecond, uploadSpeedBytesPerSecond
        case sources, availability, status, downloadPriority, ed2kHash, rootHash, partHashes, categoryID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        kind = try container.decode(CoreFileKind.self, forKey: .kind)
        sizeInBytes = try container.decode(UInt64.self, forKey: .sizeInBytes)
        completedBytes = try container.decode(UInt64.self, forKey: .completedBytes)
        downloadSpeedBytesPerSecond = try container.decode(UInt64.self, forKey: .downloadSpeedBytesPerSecond)
        uploadSpeedBytesPerSecond = try container.decode(UInt64.self, forKey: .uploadSpeedBytesPerSecond)
        sources = try container.decode(Int.self, forKey: .sources)
        availability = try container.decode(Int.self, forKey: .availability)
        status = try container.decode(CoreTransferStatus.self, forKey: .status)
        downloadPriority = try container.decodeIfPresent(CoreTransferPriority.self, forKey: .downloadPriority) ?? .auto
        ed2kHash = try container.decode(String.self, forKey: .ed2kHash).uppercased()
        rootHash = try container.decodeIfPresent(String.self, forKey: .rootHash)?.uppercased()
        partHashes = try container
            .decodeIfPresent([String].self, forKey: .partHashes)?
            .map { $0.uppercased() } ?? []
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(kind, forKey: .kind)
        try container.encode(sizeInBytes, forKey: .sizeInBytes)
        try container.encode(completedBytes, forKey: .completedBytes)
        try container.encode(downloadSpeedBytesPerSecond, forKey: .downloadSpeedBytesPerSecond)
        try container.encode(uploadSpeedBytesPerSecond, forKey: .uploadSpeedBytesPerSecond)
        try container.encode(sources, forKey: .sources)
        try container.encode(availability, forKey: .availability)
        try container.encode(status, forKey: .status)
        try container.encode(downloadPriority, forKey: .downloadPriority)
        try container.encode(ed2kHash, forKey: .ed2kHash)
        try container.encodeIfPresent(rootHash, forKey: .rootHash)
        try container.encode(partHashes, forKey: .partHashes)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
    }
}

public enum CoreServerStatus: String, Codable, Equatable, Sendable {
    case connected
    case available
    case unavailable
}

public struct CoreServer: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { endpoint.address }

    public var endpoint: ED2KServerEndpoint
    public var name: String
    public var users: Int
    public var files: Int
    public var pingMilliseconds: Int
    public var status: CoreServerStatus
    public var isPreferred: Bool

    public init(
        endpoint: ED2KServerEndpoint,
        name: String? = nil,
        users: Int = 0,
        files: Int = 0,
        pingMilliseconds: Int = 0,
        status: CoreServerStatus = .available,
        isPreferred: Bool = false
    ) {
        self.endpoint = endpoint
        self.name = name ?? endpoint.address
        self.users = users
        self.files = files
        self.pingMilliseconds = pingMilliseconds
        self.status = status
        self.isPreferred = isPreferred
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case name
        case users
        case files
        case pingMilliseconds
        case status
        case isPreferred
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(ED2KServerEndpoint.self, forKey: .endpoint)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? endpoint.address
        users = try container.decodeIfPresent(Int.self, forKey: .users) ?? 0
        files = try container.decodeIfPresent(Int.self, forKey: .files) ?? 0
        pingMilliseconds = try container.decodeIfPresent(Int.self, forKey: .pingMilliseconds) ?? 0
        status = try container.decodeIfPresent(CoreServerStatus.self, forKey: .status) ?? .available
        isPreferred = try container.decodeIfPresent(Bool.self, forKey: .isPreferred) ?? false
    }
}

public struct CoreSearchResult: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { ed2kHash }

    public var fileName: String
    public var sizeInBytes: UInt64
    public var sources: Int
    public var availability: Int
    public var network: String
    public var ed2kHash: String
    public var sourceClientID: UInt32?
    public var sourceClientPort: UInt16?

    public init(
        fileName: String,
        sizeInBytes: UInt64,
        sources: Int = 0,
        availability: Int = 0,
        network: String = "eD2k",
        ed2kHash: String,
        sourceClientID: UInt32? = nil,
        sourceClientPort: UInt16? = nil
    ) {
        self.fileName = fileName
        self.sizeInBytes = sizeInBytes
        self.sources = sources
        self.availability = availability
        self.network = network
        self.ed2kHash = ed2kHash.uppercased()
        self.sourceClientID = sourceClientID
        self.sourceClientPort = sourceClientPort
    }

    private enum CodingKeys: String, CodingKey {
        case fileName
        case sizeInBytes
        case sources
        case availability
        case network
        case ed2kHash
        case sourceClientID
        case sourceClientPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        sizeInBytes = try container.decode(UInt64.self, forKey: .sizeInBytes)
        sources = try container.decodeIfPresent(Int.self, forKey: .sources) ?? 0
        availability = try container.decodeIfPresent(Int.self, forKey: .availability) ?? 0
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? "eD2k"
        ed2kHash = try container.decode(String.self, forKey: .ed2kHash).uppercased()
        sourceClientID = try container.decodeIfPresent(UInt32.self, forKey: .sourceClientID)
        sourceClientPort = try container.decodeIfPresent(UInt16.self, forKey: .sourceClientPort)
    }
}

public struct CoreNetworkSummary: Codable, Equatable, Sendable {
    public var isConnected: Bool
    public var statusText: String
    public var downloadSpeedBytesPerSecond: UInt64
    public var highID: Bool
    public var kadNodes: Int
    public var tcpPort: Int
    public var udpPort: Int

    public init(
        isConnected: Bool = false,
        statusText: String = "Offline",
        downloadSpeedBytesPerSecond: UInt64 = 0,
        highID: Bool = false,
        kadNodes: Int = 0,
        tcpPort: Int = 4662,
        udpPort: Int = 4672
    ) {
        self.isConnected = isConnected
        self.statusText = statusText
        self.downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond
        self.highID = highID
        self.kadNodes = kadNodes
        self.tcpPort = tcpPort
        self.udpPort = udpPort
    }

    private enum CodingKeys: String, CodingKey {
        case isConnected
        case statusText
        case downloadSpeedBytesPerSecond
        case highID
        case kadNodes
        case tcpPort
        case udpPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
        statusText = try container.decode(String.self, forKey: .statusText)
        downloadSpeedBytesPerSecond = try container.decodeIfPresent(
            UInt64.self,
            forKey: .downloadSpeedBytesPerSecond
        ) ?? 0
        highID = try container.decodeIfPresent(Bool.self, forKey: .highID) ?? false
        kadNodes = try container.decodeIfPresent(Int.self, forKey: .kadNodes) ?? 0
        tcpPort = try container.decodeIfPresent(Int.self, forKey: .tcpPort) ?? 4662
        udpPort = try container.decodeIfPresent(Int.self, forKey: .udpPort) ?? 4672
    }
}

public struct CoreKadSummary: Codable, Equatable, Sendable {
    public var isRunning: Bool
    public var isConnected: Bool
    public var isFirewalled: Bool
    public var nodeCount: Int
    public var activeSearchCount: Int
    public var totalKeywords: Int
    public var totalSources: Int

    public init(
        isRunning: Bool = false,
        isConnected: Bool = false,
        isFirewalled: Bool = true,
        nodeCount: Int = 0,
        activeSearchCount: Int = 0,
        totalKeywords: Int = 0,
        totalSources: Int = 0
    ) {
        self.isRunning = isRunning
        self.isConnected = isConnected
        self.isFirewalled = isFirewalled
        self.nodeCount = nodeCount
        self.activeSearchCount = activeSearchCount
        self.totalKeywords = totalKeywords
        self.totalSources = totalSources
    }
}

public enum CorePeerState: String, Codable, Equatable, Sendable {
    case connecting
    case onQueue
    case downloading
    case noNeededParts
    case tooManyConnections
    case banned
    case error
    case unknown
}

public struct CorePeerInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(ipAddress):\(port)" }
    public var ipAddress: String
    public var port: Int
    public var clientName: String
    public var clientSoftware: String
    public var state: CorePeerState
    public var downloadSpeedBytesPerSecond: Int64
    public var queueRank: Int
    public var partsAvailable: Int
    public var totalParts: Int
    public var score: Double

    public init(
        ipAddress: String,
        port: Int = 4662,
        clientName: String = "",
        clientSoftware: String = "",
        state: CorePeerState = .unknown,
        downloadSpeedBytesPerSecond: Int64 = 0,
        queueRank: Int = 0,
        partsAvailable: Int = 0,
        totalParts: Int = 0,
        score: Double = 1.0
    ) {
        self.ipAddress = ipAddress
        self.port = port
        self.clientName = clientName
        self.clientSoftware = clientSoftware
        self.state = state
        self.downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond
        self.queueRank = queueRank
        self.partsAvailable = partsAvailable
        self.totalParts = totalParts
        self.score = score
    }
}

public struct CoreCategory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var color: String
    public var incomingDirectoryOverride: String?
    public var autoAssignByType: Bool
    public var autoAssignExtension: String
    public var priority: CoreTransferStatus

    public init(
        id: UUID = UUID(),
        title: String,
        color: String = "blue",
        incomingDirectoryOverride: String? = nil,
        autoAssignByType: Bool = false,
        autoAssignExtension: String = "",
        priority: CoreTransferStatus = .queued
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.incomingDirectoryOverride = incomingDirectoryOverride
        self.autoAssignByType = autoAssignByType
        self.autoAssignExtension = autoAssignExtension
        self.priority = priority
    }

    public static let defaultCategories: [CoreCategory] = [
        CoreCategory(title: "Video", color: "red", autoAssignByType: true, autoAssignExtension: "avi,mkv,mp4,mov,m4v,webm"),
        CoreCategory(title: "Audio", color: "purple", autoAssignByType: true, autoAssignExtension: "mp3,flac,wav,aac,ogg,m4a"),
        CoreCategory(title: "Archives", color: "orange", autoAssignByType: true, autoAssignExtension: "zip,rar,7z,tar,gz,dmg,iso"),
        CoreCategory(title: "Applications", color: "blue", autoAssignByType: true, autoAssignExtension: "app,dmg,pkg"),
        CoreCategory(title: "Documents", color: "green", autoAssignByType: true, autoAssignExtension: "pdf,doc,docx,txt,epub"),
        CoreCategory(title: "Other", color: "gray", autoAssignByType: false, autoAssignExtension: ""),
    ]
}

public struct CoreSnapshot: Codable, Equatable, Sendable {
    public var transfers: [CoreTransfer]
    public var servers: [CoreServer]
    public var searchResults: [CoreSearchResult]
    public var network: CoreNetworkSummary
    public var kad: CoreKadSummary
    public var transferPeers: [UUID: [CorePeerInfo]]
    public var categories: [CoreCategory]

    public init(
        transfers: [CoreTransfer] = [],
        servers: [CoreServer] = [],
        searchResults: [CoreSearchResult] = [],
        network: CoreNetworkSummary = CoreNetworkSummary(),
        kad: CoreKadSummary = CoreKadSummary(),
        transferPeers: [UUID: [CorePeerInfo]] = [:],
        categories: [CoreCategory] = CoreCategory.defaultCategories
    ) {
        self.transfers = transfers
        self.servers = servers
        self.searchResults = searchResults
        self.network = network
        self.kad = kad
        self.transferPeers = transferPeers
        self.categories = categories
    }

    private enum CodingKeys: String, CodingKey {
        case transfers, servers, searchResults, network, kad, transferPeers, categories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transfers = try container.decodeIfPresent([CoreTransfer].self, forKey: .transfers) ?? []
        servers = try container.decodeIfPresent([CoreServer].self, forKey: .servers) ?? []
        searchResults = try container.decodeIfPresent([CoreSearchResult].self, forKey: .searchResults) ?? []
        network = try container.decodeIfPresent(CoreNetworkSummary.self, forKey: .network) ?? CoreNetworkSummary()
        kad = try container.decodeIfPresent(CoreKadSummary.self, forKey: .kad) ?? CoreKadSummary()
        transferPeers = try container.decodeIfPresent([UUID: [CorePeerInfo]].self, forKey: .transferPeers) ?? [:]
        categories = try container.decodeIfPresent([CoreCategory].self, forKey: .categories) ?? CoreCategory.defaultCategories
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transfers, forKey: .transfers)
        try container.encode(servers, forKey: .servers)
        try container.encode(searchResults, forKey: .searchResults)
        try container.encode(network, forKey: .network)
        try container.encode(kad, forKey: .kad)
        try container.encode(transferPeers, forKey: .transferPeers)
        try container.encode(categories, forKey: .categories)
    }

    public static let empty = CoreSnapshot()
}

public enum CoreEventKind: String, Codable, Equatable, Sendable {
    case transferAdded
    case transferUpdated
    case transferRemoved
    case networkUpdated
    case kadUpdated
    case kadSearchResult
}

public struct CoreEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UInt64 { sequence }

    public let sequence: UInt64
    public var kind: CoreEventKind
    public var transferID: UUID?
    public var transfer: CoreTransfer?

    public init(
        sequence: UInt64,
        kind: CoreEventKind,
        transferID: UUID? = nil,
        transfer: CoreTransfer? = nil
    ) {
        self.sequence = sequence
        self.kind = kind
        self.transferID = transferID
        self.transfer = transfer
    }
}

public struct CoreEventBatch: Codable, Equatable, Sendable {
    public var afterSequence: UInt64
    public var latestSequence: UInt64
    public var events: [CoreEvent]
    public var snapshot: CoreSnapshot

    public init(
        afterSequence: UInt64,
        latestSequence: UInt64,
        events: [CoreEvent],
        snapshot: CoreSnapshot
    ) {
        self.afterSequence = afterSequence
        self.latestSequence = latestSequence
        self.events = events
        self.snapshot = snapshot
    }
}
