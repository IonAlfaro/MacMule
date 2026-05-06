import Foundation

public struct KadPreferences: Codable, Equatable, Sendable {
    public var kadPort: UInt16
    public var externalKadPort: UInt16
    public var bootstrapNodes: [KadEndpoint]
    public var lastSelfNodeID: KadUInt128

    public init(
        kadPort: UInt16 = 4662,
        externalKadPort: UInt16 = 0,
        bootstrapNodes: [KadEndpoint] = KadPreferences.defaultBootstrapNodes,
        lastSelfNodeID: KadUInt128 = KadUInt128.random()
    ) {
        self.kadPort = kadPort
        self.externalKadPort = externalKadPort
        self.bootstrapNodes = bootstrapNodes
        self.lastSelfNodeID = lastSelfNodeID
    }

    public static var defaultBootstrapNodes: [KadEndpoint] {
        [
            KadEndpoint(ipAddress: "emule-peer.co.uk", port: 4662),
            KadEndpoint(ipAddress: "emule.iselido.net", port: 4661),
            KadEndpoint(ipAddress: "emule-security.net", port: 4661),
            KadEndpoint(ipAddress: "upd.emule-security.net", port: 7111),
            KadEndpoint(ipAddress: "nodes.emule-security.net", port: 7111),
        ]
    }
}

public final class KadPrefsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> KadPreferences {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return KadPreferences()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(KadPreferences.self, from: data)
    }

    public func save(_ prefs: KadPreferences) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try JSONEncoder().encode(prefs)
        try data.write(to: fileURL, options: .atomic)
    }
}
