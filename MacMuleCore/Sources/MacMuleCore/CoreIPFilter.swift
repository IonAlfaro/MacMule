import Foundation

// MARK: - IP Range

public struct IPRange: Equatable, Sendable {
    public let start: UInt32
    public let end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public func contains(ip: UInt32) -> Bool {
        ip >= start && ip <= end
    }
}

// MARK: - IP Filter

/// IP range filter to block unwanted networks.
public final class CoreIPFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var ranges: [IPRange] = []

    public init() {}

    /// Loads an IP filter file.
    /// Supported: one entry per line, format "1.2.3.4 - 5.6.7.8" or CIDR "1.2.3.0/24".
    public func load(from url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var parsed: [IPRange] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if trimmed.contains("-") {
                let parts = trimmed.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2,
                      let start = ipv4ToUInt32(parts[0]),
                      let end = ipv4ToUInt32(parts[1]) else { continue }
                parsed.append(IPRange(start: start, end: end))
            } else if trimmed.contains("/") {
                let parts = trimmed.components(separatedBy: "/")
                guard parts.count == 2,
                      let ip = ipv4ToUInt32(parts[0]),
                      let prefix = Int(parts[1]),
                      prefix >= 0, prefix <= 32 else { continue }
                let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
                let network = ip & mask
                let broadcast = network | ~mask
                parsed.append(IPRange(start: network, end: broadcast))
            } else {
                guard let ip = ipv4ToUInt32(trimmed) else { continue }
                parsed.append(IPRange(start: ip, end: ip))
            }
        }

        lock.lock()
        ranges = parsed
        lock.unlock()
    }

    /// Checks whether an IP is blocked.
    public func isBlocked(ip: String) -> Bool {
        guard let addr = ipv4ToUInt32(ip) else { return false }

        lock.lock()
        defer { lock.unlock() }

        return ranges.contains { $0.contains(ip: addr) }
    }

    /// Total number of blocked ranges.
    public var blockedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return ranges.count
    }
}

// MARK: - Utilities

private func ipv4ToUInt32(_ ip: String) -> UInt32? {
    let octets = ip.components(separatedBy: ".")
    guard octets.count == 4,
          let a = UInt8(octets[0]),
          let b = UInt8(octets[1]),
          let c = UInt8(octets[2]),
          let d = UInt8(octets[3]) else { return nil }
    return (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
}
