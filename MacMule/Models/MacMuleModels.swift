            import Foundation

enum DownloadSortOrder: String, CaseIterable, Identifiable {
    case dateAdded
    case name
    case progress
    case speed
    case size
    case sources

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: "Date"
        case .name: "Name"
        case .progress: "Progress"
        case .speed: "Speed"
        case .size: "Size"
        case .sources: "Sources"
        }
    }

    var systemImage: String {
        switch self {
        case .dateAdded: "calendar"
        case .name: "textformat.abc"
        case .progress: "arrow.down.circle"
        case .speed: "speedometer"
        case .size: "scalemass"
        case .sources: "person.2"
        }
    }

    func comparator(_ a: TransferItem, _ b: TransferItem) -> Bool {
        switch self {
        case .dateAdded:
            return true // items are already in order
        case .name:
            return a.fileName.localizedCaseInsensitiveCompare(b.fileName) == .orderedAscending
        case .progress:
            return a.progress > b.progress
        case .speed:
            return a.downloadSpeedBytesPerSecond > b.downloadSpeedBytesPerSecond
        case .size:
            return a.sizeInBytes > b.sizeInBytes
        case .sources:
            return a.sources > b.sources
        }
    }
}

enum MacMuleSection: String, CaseIterable, Identifiable {
    case dashboard
    case search
    case downloads
    case uploads
    case shared
    case kad
    case network
    case statistics
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Home"
        case .search: "Search"
        case .downloads: "Downloads"
        case .uploads: "Uploads"
        case .shared: "Shared"
        case .kad: "Kad"
        case .network: "Servers"
        case .statistics: "Statistics"
        case .settings: "Settings"
        case .logs: "Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down.circle"
        case .uploads: "arrow.up.circle"
        case .shared: "folder"
        case .kad: "circle.hexagongrid"
        case .network: "server.rack"
        case .statistics: "chart.xyaxis.line"
        case .settings: "gearshape"
        case .logs: "text.alignleft"
        }
    }
}

enum FileKind: String, CaseIterable, Hashable {
    case video
    case audio
    case archive
    case document
    case application
    case other

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .archive: "Archive"
        case .document: "Document"
        case .application: "App"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .archive: "archivebox"
        case .document: "doc.text"
        case .application: "app.dashed"
        case .other: "doc"
        }
    }

    nonisolated static func inferred(from fileName: String) -> FileKind {
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

enum TransferStatus: String, CaseIterable, Hashable {
    case queued
    case downloading
    case paused
    case verifying
    case completed
    case failed

    var title: String {
        switch self {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .verifying: "Verifying"
        case .completed: "Completed"
        case .failed: "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: "clock"
        case .downloading: "arrow.down"
        case .paused: "pause"
        case .verifying: "checkmark.shield"
        case .completed: "checkmark"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum ChunkState: String, Hashable {
    case missing
    case queued
    case active
    case complete
    case corrupt
}

struct TransferItem: Identifiable, Hashable {
    let id: UUID
    var fileName: String
    var kind: FileKind
    var sizeInBytes: Int64
    var completedBytes: Int64
    var downloadSpeedBytesPerSecond: Int64
    var uploadSpeedBytesPerSecond: Int64
    var sources: Int
    var availability: Int
    var status: TransferStatus
    var ed2kHash: String
    var chunks: [ChunkState]

    nonisolated init(
        id: UUID = UUID(),
        fileName: String,
        kind: FileKind,
        sizeInBytes: Int64,
        completedBytes: Int64,
        downloadSpeedBytesPerSecond: Int64,
        uploadSpeedBytesPerSecond: Int64,
        sources: Int,
        availability: Int,
        status: TransferStatus,
        ed2kHash: String,
        chunks: [ChunkState]
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
        self.ed2kHash = ed2kHash
        self.chunks = chunks
    }

    var progress: Double {
        guard sizeInBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(sizeInBytes), 0), 1)
    }

    var sizeText: String {
        ByteCountFormatter.macMuleString(sizeInBytes)
    }

    var completedText: String {
        ByteCountFormatter.macMuleString(completedBytes)
    }

    var downloadSpeedText: String {
        ByteCountFormatter.macMuleString(downloadSpeedBytesPerSecond) + "/s"
    }

    var uploadSpeedText: String {
        ByteCountFormatter.macMuleString(uploadSpeedBytesPerSecond) + "/s"
    }

    var estimatedTimeRemaining: TimeInterval? {
        let remaining = sizeInBytes - completedBytes
        guard remaining > 0, downloadSpeedBytesPerSecond > 0 else { return nil }
        return TimeInterval(remaining) / TimeInterval(downloadSpeedBytesPerSecond)
    }

    var estimatedTimeRemainingText: String {
        guard let eta = estimatedTimeRemaining, eta.isFinite else { return "—" }
        if eta < 60 { return "\(Int(eta)) s" }
        if eta < 3600 {
            let m = Int(eta / 60)
            let s = Int(eta.truncatingRemainder(dividingBy: 60))
            return "\(m) m \(s) s"
        }
        let h = Int(eta / 3600)
        let m = Int((eta.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h) h \(m) m"
    }
}

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    var fileName: String
    var kind: FileKind
    var sizeInBytes: Int64
    var sources: Int
    var availability: Int
    var network: String
    var ed2kHash: String
    var sourceClientID: UInt32? = nil
    var sourceClientPort: UInt16? = nil

    var sizeText: String {
        ByteCountFormatter.macMuleString(sizeInBytes)
    }
}

enum ServerHealth: String, Hashable {
    case connected
    case available
    case unavailable

    var title: String {
        switch self {
        case .connected: "Connected"
        case .available: "Available"
        case .unavailable: "No response"
        }
    }
}

struct ServerSnapshot: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var address: String
    var users: Int
    var files: Int
    var pingMilliseconds: Int
    var health: ServerHealth
    var isPreferred: Bool
}

struct NetworkSummary: Hashable {
    var isConnected: Bool
    var statusText: String
    var downloadSpeedBytesPerSecond: Int64 = 0
    var highID: Bool
    var kadNodes: Int
    var tcpPort: Int
    var udpPort: Int
}

struct SharedFile: Identifiable, Hashable {
    let id = UUID()
    var fileName: String
    var kind: FileKind
    var sizeInBytes: Int64
    var requests: Int
    var uploadedBytes: Int64

    var sizeText: String {
        ByteCountFormatter.macMuleString(sizeInBytes)
    }

    var uploadedText: String {
        ByteCountFormatter.macMuleString(uploadedBytes)
    }
}

struct KadSummary: Hashable {
    var isRunning: Bool
    var isConnected: Bool
    var isFirewalled: Bool
    var nodeCount: Int
    var activeSearchCount: Int
    var totalKeywords: Int
    var totalSources: Int
}

struct KadNode: Identifiable, Hashable {
    let id: String
    var nodeIDPrefix: String
    var ipAddress: String
    var udpPort: Int
    var tcpPort: Int
    var version: Int
    var distance: String
    var lastSeen: Date

    var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
}

struct KadBucketStat: Identifiable, Hashable {
    let id: Int
    var depth: Int
    var count: Int
    var maxSize: Int
    var prefixBits: String

    var fullness: Double {
        Double(count) / Double(maxSize)
    }
}

struct KadSearchSummary: Identifiable, Hashable {
    let id: String
    var type: String
    var targetHex: String
    var startedAt: Date
    var results: Int
    var nodesQueried: Int
    var isComplete: Bool

    var elapsedText: String {
        let interval = isComplete ? 0 : Date().timeIntervalSince(startedAt)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: interval) ?? "0s"
    }
}

struct StatMetric: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var value: String
    var systemImage: String
}

enum SearchMethod: String, CaseIterable {
    case server = "Server"
    case kad = "Kad"
}

struct SourceDetail: Identifiable, Hashable {
    let id: String
    var clientName: String
    var clientSoftware: String
    var ipAddress: String
    var port: Int
    var state: SourceState
    var queueRank: Int
    var downloadSpeedBytesPerSecond: Int64
    var partsAvailable: Int
    var totalParts: Int
    var lastSeen: Date
    var a4afFiles: [String]
    var score: Double

    var stateText: String {
        switch state {
        case .connecting: "Connecting"
        case .onQueue: "Queued (\(queueRank))"
        case .downloading: "Downloading"
        case .noNeededParts: "No needed parts"
        case .tooManyConnections: "Too many connections"
        case .banned: "Banned"
        case .error: "Error"
        }
    }
}

enum SourceState: String, Hashable, CaseIterable {
    case connecting
    case onQueue
    case downloading
    case noNeededParts
    case tooManyConnections
    case banned
    case error
}

extension ByteCountFormatter {
    nonisolated static func macMuleString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
