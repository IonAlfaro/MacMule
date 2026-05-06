import Foundation

public final class KadNodesStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadNodes() throws -> [KadContact] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var contacts: [KadContact] = []

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: ",")
            guard parts.count >= 5 else { continue }

            guard let rawNodeID = hexToData(String(parts[0])),
                  rawNodeID.count == 16 else { continue }

            let ip = String(parts[1])
            guard let udpPort = UInt16(parts[2]),
                  let tcpPort = UInt16(parts[3]),
                  let version = UInt8(parts[4]) else { continue }

            let lastSeen: Date
            if parts.count > 5, let timestamp = TimeInterval(parts[5]) {
                lastSeen = Date(timeIntervalSince1970: timestamp)
            } else {
                lastSeen = Date()
            }

            let contact = KadContact(
                nodeID: KadUInt128(data: rawNodeID),
                ipAddress: ip,
                udpPort: udpPort,
                tcpPort: tcpPort,
                kadVersion: version,
                lastSeen: lastSeen,
                verified: true
            )
            contacts.append(contact)
        }

        return contacts
    }

    public func saveNodes(_ contacts: [KadContact]) throws {
        lock.lock()
        defer { lock.unlock() }

        let lines = contacts.map { contact in
            let timestamp = Int64(contact.lastSeen.timeIntervalSince1970)
            return "\(contact.nodeID.hexString),\(contact.ipAddress),\(contact.udpPort),\(contact.tcpPort),\(contact.kadVersion),\(timestamp)"
        }

        let content = "# MacMule Kad nodes.dat\n# Format: nodeID,ip,udpPort,tcpPort,version,lastSeen\n"
            + lines.joined(separator: "\n") + "\n"

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func mergeNodes(_ newContacts: [KadContact], with existing: [KadContact], maxNodes: Int = 5000) -> [KadContact] {
        var map: [KadUInt128: KadContact] = [:]

        for contact in existing {
            map[contact.nodeID] = contact
        }

        for contact in newContacts {
            if let existing = map[contact.nodeID] {
                if contact.lastSeen > existing.lastSeen {
                    map[contact.nodeID] = contact
                }
            } else {
                map[contact.nodeID] = contact
            }
        }

        return Array(map.values)
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(maxNodes)
            .map { $0 }
    }

    private func hexToData(_ hex: String) -> Data? {
        let clean = hex.replacingOccurrences(of: " ", with: "")
        guard clean.count % 2 == 0 else { return nil }

        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index ..< nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
