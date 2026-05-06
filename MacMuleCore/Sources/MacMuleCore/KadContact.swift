import Foundation

public struct KadContact: Identifiable, Equatable, Hashable, Sendable, Codable {
    public var id: KadUInt128 { nodeID }
    public var nodeID: KadUInt128
    public var ipAddress: String
    public var udpPort: UInt16
    public var tcpPort: UInt16
    public var kadVersion: UInt8
    public var lastSeen: Date
    public var verified: Bool

    public init(
        nodeID: KadUInt128,
        ipAddress: String,
        udpPort: UInt16,
        tcpPort: UInt16,
        kadVersion: UInt8 = 9,
        lastSeen: Date = Date(),
        verified: Bool = false
    ) {
        self.nodeID = nodeID
        self.ipAddress = ipAddress
        self.udpPort = udpPort
        self.tcpPort = tcpPort
        self.kadVersion = kadVersion
        self.lastSeen = lastSeen
        self.verified = verified
    }

    public var endpoint: KadEndpoint {
        KadEndpoint(ipAddress: ipAddress, port: udpPort)
    }

    public func distance(to other: KadUInt128) -> KadUInt128 {
        nodeID ^ other
    }

    public func touch() -> KadContact {
        var copy = self
        copy.lastSeen = Date()
        return copy
    }

    public var isExpired: Bool {
        Date().timeIntervalSince(lastSeen) > KadConstants.contactTimeout
    }
}

public struct KadEndpoint: Equatable, Hashable, Sendable, Codable {
    public var ipAddress: String
    public var port: UInt16

    public init(ipAddress: String, port: UInt16) {
        self.ipAddress = ipAddress
        self.port = port
    }
}
