import Foundation

public struct CoreUploadSlot: Equatable, Sendable, Codable {
    public var clientID: KadUInt128
    public var clientIP: String
    public var clientPort: UInt16
    public var fileName: String
    public var fileHash: Data
    public var fileSize: UInt64
    public var uploadedBytes: UInt64
    public var uploadSpeed: UInt64
    public var requestedChunks: Int
    public var completedChunks: Int
    public var startedAt: Date
    public var lastActivity: Date
    public var queueRank: UInt32
    public var score: Double

    public init(
        clientID: KadUInt128,
        clientIP: String,
        clientPort: UInt16,
        fileName: String,
        fileHash: Data,
        fileSize: UInt64 = 0,
        uploadedBytes: UInt64 = 0,
        uploadSpeed: UInt64 = 0,
        requestedChunks: Int = 0,
        completedChunks: Int = 0,
        startedAt: Date = Date(),
        lastActivity: Date = Date(),
        queueRank: UInt32 = 0,
        score: Double = 1.0
    ) {
        self.clientID = clientID
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.fileName = fileName
        self.fileHash = fileHash
        self.fileSize = fileSize
        self.uploadedBytes = uploadedBytes
        self.uploadSpeed = uploadSpeed
        self.requestedChunks = requestedChunks
        self.completedChunks = completedChunks
        self.startedAt = startedAt
        self.lastActivity = lastActivity
        self.queueRank = queueRank
        self.score = score
    }
}

public struct CoreWaitingClient: Equatable, Sendable, Codable {
    public var clientID: KadUInt128
    public var clientIP: String
    public var clientPort: UInt16
    public var fileName: String
    public var fileHash: Data
    public var queueRank: UInt32
    public var score: Double
    public var waitStartTime: Date
    public var retryCount: Int

    public init(
        clientID: KadUInt128,
        clientIP: String,
        clientPort: UInt16,
        fileName: String,
        fileHash: Data,
        queueRank: UInt32 = 0,
        score: Double = 1.0,
        waitStartTime: Date = Date(),
        retryCount: Int = 0
    ) {
        self.clientID = clientID
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.fileName = fileName
        self.fileHash = fileHash
        self.queueRank = queueRank
        self.score = score
        self.waitStartTime = waitStartTime
        self.retryCount = retryCount
    }
}

public enum CoreUploadState: String, Codable, Equatable, Sendable {
    case active
    case waiting
    case paused
}

public final class CoreUploadQueue: @unchecked Sendable {
    private let lock = NSLock()

    public var maxActiveSlots: Int = 5
    public var maxUploadSpeed: UInt64 = 0

    private var activeUploads: [KadUInt128: CoreUploadSlot] = [:]
    private var waitingClients: [KadUInt128: CoreWaitingClient] = [:]
    private var pausedUploadIDs: Set<KadUInt128> = []

    public var totalUploadedBytes: UInt64 = 0
    public var successfulUploads: Int = 0
    public var failedUploads: Int = 0

    public init(maxActiveSlots: Int = 5, maxUploadSpeed: UInt64 = 0) {
        self.maxActiveSlots = maxActiveSlots
        self.maxUploadSpeed = maxUploadSpeed
    }

    public func addClientToWaiting(
        clientID: KadUInt128,
        clientIP: String,
        clientPort: UInt16,
        fileName: String,
        fileHash: Data,
        score: Double = 1.0
    ) -> CoreWaitingClient {
        lock.lock()
        defer { lock.unlock() }

        let client = CoreWaitingClient(
            clientID: clientID,
            clientIP: clientIP,
            clientPort: clientPort,
            fileName: fileName,
            fileHash: fileHash,
            score: score
        )
        waitingClients[clientID] = client
        return client
    }

    public func acceptNextClient() -> CoreUploadSlot? {
        lock.lock()
        defer { lock.unlock() }

        guard activeUploads.count < maxActiveSlots else { return nil }

        let sorted = waitingClients.values.sorted { a, b in
            if abs(a.score - b.score) > 0.01 { return a.score > b.score }
            return a.waitStartTime < b.waitStartTime
        }

        guard let best = sorted.first else { return nil }

        waitingClients.removeValue(forKey: best.clientID)

        let slot = CoreUploadSlot(
            clientID: best.clientID,
            clientIP: best.clientIP,
            clientPort: best.clientPort,
            fileName: best.fileName,
            fileHash: best.fileHash,
            score: best.score
        )
        activeUploads[best.clientID] = slot
        return slot
    }

    public func completeUpload(clientID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }
        activeUploads.removeValue(forKey: clientID)
        successfulUploads += 1
    }

    public func failUpload(clientID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }

        if let slot = activeUploads.removeValue(forKey: clientID) {
            failedUploads += 1
            let waiting = CoreWaitingClient(
                clientID: slot.clientID,
                clientIP: slot.clientIP,
                clientPort: slot.clientPort,
                fileName: slot.fileName,
                fileHash: slot.fileHash,
                score: slot.score * 0.5,
                retryCount: 1
            )
            waitingClients[slot.clientID] = waiting
        }
    }

    public func recordBytes(clientID: KadUInt128, bytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        guard var slot = activeUploads[clientID] else { return }
        slot.uploadedBytes += bytes
        slot.lastActivity = Date()
        totalUploadedBytes += bytes
        activeUploads[clientID] = slot
    }

    public func removeClient(clientID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }
        activeUploads.removeValue(forKey: clientID)
        waitingClients.removeValue(forKey: clientID)
        pausedUploadIDs.remove(clientID)
    }

    public func pauseClient(clientID: KadUInt128) {
        lock.lock()
        defer { lock.unlock() }

        if activeUploads.removeValue(forKey: clientID) != nil {
            pausedUploadIDs.insert(clientID)
        }
    }

    public func resumeClient(clientID: KadUInt128) {
        lock.lock()
        pausedUploadIDs.remove(clientID)
        lock.unlock()
    }

    public func activeSlots() -> [CoreUploadSlot] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeUploads.values)
    }

    public func waitingList() -> [CoreWaitingClient] {
        lock.lock()
        defer { lock.unlock() }
        return waitingClients.values.sorted { $0.score > $1.score }
    }

    public var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeUploads.count
    }

    public var waitingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waitingClients.count
    }

    public var aggregateUploadSpeed: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return activeUploads.values.reduce(0) { $0 + $1.uploadSpeed }
    }

    public func updateSpeeds() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        for (id, var slot) in activeUploads {
            let elapsed = max(now.timeIntervalSince(slot.lastActivity), 0.001)
            slot.uploadSpeed = UInt64(Double(slot.uploadedBytes) / elapsed)
            activeUploads[id] = slot
        }
    }
}
