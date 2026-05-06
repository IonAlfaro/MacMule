import Foundation

public final class KadPacketTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [KadUInt128: PendingRequest]
    private var nextTransactionID: UInt8 = 0

    public init() {
        self.pending = [:]
    }

    public func nextID() -> KadUInt128 {
        lock.lock()
        defer { lock.unlock() }
        nextTransactionID = nextTransactionID &+ 1
        return KadUInt128(lo: UInt64(nextTransactionID))
    }

    public func track(send targetNodeID: KadUInt128, transaction: KadUInt128, expectedResponse: KadPacketOpcode, timeout: TimeInterval = 10) {
        let request = PendingRequest(
            transactionID: transaction,
            targetNodeID: targetNodeID,
            expectedResponse: expectedResponse,
            sentAt: Date(),
            timeout: timeout
        )
        lock.lock()
        pending[transaction] = request
        lock.unlock()
    }

    public func matchResponse(opcode: KadPacketOpcode, transaction: KadUInt128) -> PendingRequest? {
        lock.lock()
        defer { lock.unlock() }

        guard let request = pending[transaction],
              request.expectedResponse == opcode else {
            return nil
        }

        pending.removeValue(forKey: transaction)
        return request
    }

    public func expireAndCollect() -> [PendingRequest] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let expired = pending.values.filter { now.timeIntervalSince($0.sentAt) > $0.timeout }
        for request in expired {
            pending.removeValue(forKey: request.transactionID)
        }
        return expired
    }

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    public func cancelAll() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
    }

    public struct PendingRequest: Equatable, Sendable {
        public let transactionID: KadUInt128
        public let targetNodeID: KadUInt128
        public let expectedResponse: KadPacketOpcode
        public let sentAt: Date
        public let timeout: TimeInterval

        public init(
            transactionID: KadUInt128,
            targetNodeID: KadUInt128,
            expectedResponse: KadPacketOpcode,
            sentAt: Date,
            timeout: TimeInterval
        ) {
            self.transactionID = transactionID
            self.targetNodeID = targetNodeID
            self.expectedResponse = expectedResponse
            self.sentAt = sentAt
            self.timeout = timeout
        }
    }
}
