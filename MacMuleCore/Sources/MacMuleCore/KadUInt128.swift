import Foundation

public struct KadUInt128: Equatable, Hashable, Sendable, Codable {
    public var hi: UInt64
    public var lo: UInt64

    public init(hi: UInt64 = 0, lo: UInt64 = 0) {
        self.hi = hi
        self.lo = lo
    }

    public init(data: Data) {
        var d = data
        if d.count < 16 {
            let padding = Data(repeating: 0, count: 16 - d.count)
            d = padding + d
        }
        self.hi = UInt64(bigEndian: d.withUnsafeBytes { $0.load(as: UInt64.self) })
        self.lo = UInt64(bigEndian: d.dropFirst(8).withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    public var data: Data {
        var result = Data(count: 16)
        result.withUnsafeMutableBytes {
            $0.storeBytes(of: hi.bigEndian, as: UInt64.self)
            ($0.baseAddress! + 8).storeBytes(of: lo.bigEndian, as: UInt64.self)
        }
        return result
    }

    public var hexString: String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func ^ (lhs: KadUInt128, rhs: KadUInt128) -> KadUInt128 {
        KadUInt128(hi: lhs.hi ^ rhs.hi, lo: lhs.lo ^ rhs.lo)
    }

    public static func < (lhs: KadUInt128, rhs: KadUInt128) -> Bool {
        if lhs.hi != rhs.hi { return lhs.hi < rhs.hi }
        return lhs.lo < rhs.lo
    }

    public var bitCount: Int {
        var bits = 0
        if hi > 0 {
            bits = 64 + (64 - hi.leadingZeroBitCount)
        } else if lo > 0 {
            bits = 64 - lo.leadingZeroBitCount
        }
        return bits
    }

    public func commonPrefixBits(with other: KadUInt128) -> Int {
        let diff = self ^ other
        return 128 - diff.bitCount
    }

    public func bitAt(_ position: Int) -> Bool {
        let bitIndex = position
        guard bitIndex >= 0, bitIndex < 128 else { return false }
        if bitIndex < 64 {
            return (lo >> (63 - bitIndex)) & 1 == 1
        } else {
            return (hi >> (127 - bitIndex)) & 1 == 1
        }
    }

    public static func random() -> KadUInt128 {
        KadUInt128(hi: UInt64.random(in: .min ... .max), lo: UInt64.random(in: .min ... .max))
    }
}
