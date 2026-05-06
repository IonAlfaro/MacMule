import Foundation

/// Parses eMule `server.met` binary files and plain-text server lists.
/// Returns an array of `(host, port)` tuples ready to pass to `addServer`.
enum ServerMetParser {

    // MARK: - Public API

    /// Detect format and parse. Returns all successfully parsed entries.
    static func parse(_ data: Data) -> [(host: String, port: UInt16)] {
        // Try binary server.met first (magic byte 0x0E or 0xE0)
        if let first = data.first, first == 0x0E || first == 0xE0 {
            let result = parseBinaryMet(data)
            if result.isEmpty == false { return result }
        }
        // Fallback: text list  (one "host:port" per line, or comma/semicolon separated)
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return parseTextList(text)
        }
        return []
    }

    // MARK: - Binary server.met parser

    /// Parses the binary server.met format used by eMule/eDonkey2000.
    ///
    /// Layout:
    /// ```
    /// [1]  version: 0x0E (old) | 0xE0 (new, has 4-byte timestamp after)
    /// [4]  server count (uint32 LE)
    /// per server:
    ///   [4]  IP as 4 bytes, stored A.B.C.D in file order (first octet first)
    ///   [2]  port (uint16 LE)
    ///   [4]  tag count (uint32 LE)
    ///   per tag:
    ///     [1]  value type
    ///     [2]  tag name length
    ///     [n]  tag name bytes (0x01 = server name, etc.)
    ///     ...  value (type-dependent)
    /// ```
    private static func parseBinaryMet(_ data: Data) -> [(host: String, port: UInt16)] {
        var offset = 0

        guard let version = readByte(data, at: &offset) else { return [] }
        guard version == 0x0E || version == 0xE0 else { return [] }

        // New format has a 4-byte date field after the version
        if version == 0xE0 { offset += 4 }

        guard let count = readUInt32LE(data, at: &offset) else { return [] }
        guard count > 0 && count < 50_000 else { return [] } // sanity check

        var results: [(host: String, port: UInt16)] = []
        results.reserveCapacity(Int(count))

        for _ in 0..<count {
            // IP: 4 bytes in dotted-notation order (b[0] = first octet)
            guard offset + 4 <= data.count else { break }
            let host = "\(data[offset]).\(data[offset+1]).\(data[offset+2]).\(data[offset+3])"
            offset += 4

            guard let port = readUInt16LE(data, at: &offset) else { break }
            guard let tagCount = readUInt32LE(data, at: &offset) else { break }
            guard tagCount < 100 else { break } // sanity

            var ok = true
            for _ in 0..<tagCount {
                if !skipTag(data, offset: &offset) { ok = false; break }
            }

            if port > 0 {
                results.append((host: host, port: port))
            }
            if !ok { break }
        }

        return results
    }

    // MARK: - Tag skipping

    /// Skips one tag, advancing `offset`. Returns false if data is truncated.
    private static func skipTag(_ data: Data, offset: inout Int) -> Bool {
        guard let rawType = readByte(data, at: &offset) else { return false }

        // The name is encoded as: 2-byte length + N bytes
        guard let nameLen = readUInt16LE(data, at: &offset) else { return false }
        guard offset + Int(nameLen) <= data.count else { return false }
        offset += Int(nameLen)

        return skipTagValue(data, type: rawType, offset: &offset)
    }

    private static func skipTagValue(_ data: Data, type rawType: UInt8, offset: inout Int) -> Bool {
        let type_ = rawType & 0x7F // mask away the "special name" flag if any

        switch type_ {
        case 0x01: // hash (16 bytes)
            guard offset + 16 <= data.count else { return false }
            offset += 16
        case 0x02: // string
            guard let len = readUInt16LE(data, at: &offset) else { return false }
            guard offset + Int(len) <= data.count else { return false }
            offset += Int(len)
        case 0x03: // uint32 / float32
            guard offset + 4 <= data.count else { return false }
            offset += 4
        case 0x04: // float32 (same as uint32)
            guard offset + 4 <= data.count else { return false }
            offset += 4
        case 0x05: // bool (1 byte)
            guard offset + 1 <= data.count else { return false }
            offset += 1
        case 0x06: // bool array — 2 bytes
            guard offset + 2 <= data.count else { return false }
            offset += 2
        case 0x08: // uint16
            guard offset + 2 <= data.count else { return false }
            offset += 2
        case 0x09: // uint8
            guard offset + 1 <= data.count else { return false }
            offset += 1
        case 0x0A: // uint64
            guard offset + 8 <= data.count else { return false }
            offset += 8
        case 0x0B: // uint16 (BSOB)
            guard offset + 2 <= data.count else { return false }
            offset += 2
        case 0x0F: // blob — 4-byte length then bytes
            guard let len = readUInt32LE(data, at: &offset) else { return false }
            guard offset + Int(len) <= data.count else { return false }
            offset += Int(len)
        default:
            // Short string types: 0x11..0x20 → length = (type - 0x10) bytes
            if type_ >= 0x11 && type_ <= 0x20 {
                let len = Int(type_ - 0x10)
                guard offset + len <= data.count else { return false }
                offset += len
            } else {
                // Unknown type — give up parsing this server
                return false
            }
        }
        return true
    }

    // MARK: - Text list parser

    /// Parses text server lists.
    /// Supported formats:
    /// - `host:port` one per line
    /// - Comma or semicolon separated `host:port` values
    private static func parseTextList(_ text: String) -> [(host: String, port: UInt16)] {
        let separators = CharacterSet(charactersIn: ",;\n\r")
        return text
            .components(separatedBy: separators)
            .compactMap { entry -> (host: String, port: UInt16)? in
                let trimmed = entry.trimmingCharacters(in: .whitespaces)
                guard trimmed.isEmpty == false,
                      trimmed.hasPrefix("#") == false, // skip comment lines
                      let sep = trimmed.lastIndex(of: ":") else { return nil }
                let host = String(trimmed[..<sep]).trimmingCharacters(in: .whitespaces)
                let rawPort = String(trimmed[trimmed.index(after: sep)...])
                guard host.isEmpty == false, let port = UInt16(rawPort) else { return nil }
                return (host: host, port: port)
            }
    }

    // MARK: - Read helpers

    private static func readByte(_ data: Data, at offset: inout Int) -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    private static func readUInt16LE(_ data: Data, at offset: inout Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        let lo = UInt16(data[offset])
        let hi = UInt16(data[offset + 1])
        offset += 2
        return lo | (hi << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        offset += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
