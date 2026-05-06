import Foundation

// Standard eMule part size: 9.28 MB
private let standardPartSize: UInt64 = 9_728_000

public final class CoreRarityScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var fileAvailability: [Data: [Int: Int]] = [:]

    public init() {}

    /// Returns the range of the rarest missing part, or nil if no information is available.
    public func getNextPart(
        for fileHash: Data,
        completedRanges: [ClosedRange<UInt64>],
        partAvailability: [Int: Int]
    ) -> (start: UInt64, end: UInt64)? {
        lock.lock()
        defer { lock.unlock() }

        let merged = mergeAvailability(partAvailability)
        let rarest = merged
            .sorted { a, b in a.value < b.value }
            .lazy
            .compactMap { (partIndex, _) -> (start: UInt64, end: UInt64)? in
                let start = UInt64(partIndex) * standardPartSize
                let end = start + standardPartSize - 1
                let isCompleted = completedRanges.contains { range in
                    range.lowerBound <= start && range.upperBound >= end
                }
                return isCompleted ? nil : (start, end)
            }
            .first

        return rarest
    }

    public func updateAvailability(fileHash: Data, partIndex: Int, count: Int) {
        lock.lock()
        defer { lock.unlock() }

        var parts = fileAvailability[fileHash] ?? [:]
        parts[partIndex, default: 0] += count
        fileAvailability[fileHash] = parts
    }

    public func reset(for fileHash: Data) {
        lock.lock()
        defer { lock.unlock() }

        fileAvailability.removeValue(forKey: fileHash)
    }

    // MARK: - Internal

    private func mergeAvailability(_ external: [Int: Int]) -> [Int: Int] {
        external
    }
}
