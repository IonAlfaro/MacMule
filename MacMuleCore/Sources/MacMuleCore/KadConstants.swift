import Foundation

public enum KadConstants {
    public static let kBucketSize = 10
    public static let alpha = 3
    public static let beta = 2

    public static let searchLifetime: TimeInterval = 60
    public static let publishLifetime: TimeInterval = 120
    public static let bootstrapTimeout: TimeInterval = 60

    public static let contactTimeout: TimeInterval = 3600
    public static let bucketRefreshInterval: TimeInterval = 3600
    public static let selfLookupInterval: TimeInterval = 3600

    public static let maxKeywordResults = 300
    public static let maxSourceResults = 500
    public static let maxNotesResults = 150

    public static let keywordTTL: TimeInterval = 86400
    public static let sourceTTL: TimeInterval = 21600
    public static let notesTTL: TimeInterval = 129600

    public static let publishKeywordInterval: TimeInterval = 43200
    public static let publishSourceInterval: TimeInterval = 18000
    public static let publishNotesInterval: TimeInterval = 43200

    public static let firewallCheckInterval: TimeInterval = 7200
    public static let buddyRefreshInterval: TimeInterval = 900
}

public enum KadPacketOpcode: UInt8, Codable, Equatable, Sendable {
    case bootstrapReq = 0x00
    case bootstrapRes = 0x08
    case helloReq = 0x10
    case helloRes = 0x18
    case req = 0x20
    case res = 0x28
    case searchReq = 0x30
    case searchNotesReq = 0x32
    case searchRes = 0x38
    case publishReq = 0x40
    case publishNotesReq = 0x42
    case publishRes = 0x48
    case publishNotesRes = 0x4A
    case firewallReq = 0x50
    case firewallRes = 0x58
    case firewallAck = 0x59

    public var isRequest: Bool {
        rawValue & 0x01 == 0
    }

    public var responseOpcode: KadPacketOpcode? {
        KadPacketOpcode(rawValue: rawValue | 0x08)
    }
}

public enum KadSearchType: UInt8, Codable, Equatable, Sendable {
    case keyword = 0x02
    case source = 0x03
    case notes = 0x06
    case storeKeyword = 0x09
    case storeSource = 0x0A
    case storeNotes = 0x0B
    case findNode = 0x0D
    case findValue = 0x0E
    case store = 0x0F
}

public enum KadFirewallState: String, Codable, Equatable, Sendable {
    case unknown
    case open
    case firewalled
}
