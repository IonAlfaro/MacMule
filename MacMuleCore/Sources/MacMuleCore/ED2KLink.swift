import Foundation

public struct ED2KFileLink: Codable, Equatable, Hashable, Sendable {
    public let fileName: String
    public let sizeInBytes: UInt64
    public let hash: String
    public let rootHash: String?
    public let partHashes: [String]

    public init(
        fileName: String,
        sizeInBytes: UInt64,
        hash: String,
        rootHash: String? = nil,
        partHashes: [String] = []
    ) {
        self.fileName = fileName
        self.sizeInBytes = sizeInBytes
        self.hash = hash.uppercased()
        self.rootHash = rootHash?.uppercased()
        self.partHashes = partHashes.map { $0.uppercased() }
    }

    public var canonicalURL: String {
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .ed2kFileNameAllowed) ?? fileName
        var fields = ["ed2k://", "file", encodedName, "\(sizeInBytes)", hash]

        if partHashes.isEmpty == false {
            fields.append("p=\(partHashes.joined(separator: ":"))")
        }

        if let rootHash {
            fields.append("h=\(rootHash)")
        }

        return fields.joined(separator: "|") + "|/"
    }
}

public enum ED2KLinkParseError: Error, Equatable, LocalizedError {
    case invalidScheme
    case unsupportedLinkKind(String)
    case missingField(String)
    case invalidSize(String)
    case invalidHash(String)

    public var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "The link must start with ed2k://."
        case .unsupportedLinkKind(let kind):
            return "Unsupported eD2k link kind: \(kind)."
        case .missingField(let field):
            return "Missing eD2k file field: \(field)."
        case .invalidSize(let size):
            return "Invalid eD2k file size: \(size)."
        case .invalidHash(let hash):
            return "Invalid eD2k hash: \(hash)."
        }
    }
}

public enum ED2KLinkParser {
    public static func parseFileLink(_ rawLink: String) throws -> ED2KFileLink {
        let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("ed2k://") else {
            throw ED2KLinkParseError.invalidScheme
        }

        var body = String(trimmed.dropFirst("ed2k://".count))
        if body.hasSuffix("/") {
            body.removeLast()
        }

        let fields = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 5 else {
            throw ED2KLinkParseError.missingField("file")
        }

        let kind = fields[1].lowercased()
        guard fields[0].isEmpty, kind == "file" else {
            throw ED2KLinkParseError.unsupportedLinkKind(kind.isEmpty ? fields[1] : kind)
        }

        let rawName = fields[2]
        guard rawName.isEmpty == false else {
            throw ED2KLinkParseError.missingField("name")
        }

        let rawSize = fields[3]
        guard let size = UInt64(rawSize), size > 0 else {
            throw ED2KLinkParseError.invalidSize(rawSize)
        }

        let hash = fields[4].uppercased()
        guard hash.isED2KHash else {
            throw ED2KLinkParseError.invalidHash(fields[4])
        }

        let rootHash = fields
            .dropFirst(5)
            .compactMap { field -> String? in
                guard field.lowercased().hasPrefix("h=") else { return nil }
                return String(field.dropFirst(2)).uppercased()
            }
            .first

        if let rootHash, rootHash.isED2KHash == false {
            throw ED2KLinkParseError.invalidHash(rootHash)
        }

        let partHashes = try fields
            .dropFirst(5)
            .compactMap { field -> String? in
                guard field.lowercased().hasPrefix("p=") else { return nil }
                return String(field.dropFirst(2))
            }
            .flatMap { rawHashes in
                try rawHashes
                    .split(separator: ":", omittingEmptySubsequences: true)
                    .map { hash in
                        let uppercasedHash = String(hash).uppercased()
                        guard uppercasedHash.isED2KHash else {
                            throw ED2KLinkParseError.invalidHash(String(hash))
                        }
                        return uppercasedHash
                    }
            }

        return ED2KFileLink(
            fileName: rawName.removingPercentEncoding ?? rawName,
            sizeInBytes: size,
            hash: hash,
            rootHash: rootHash,
            partHashes: partHashes
        )
    }
}

private extension String {
    var isED2KHash: Bool {
        count == 32 && allSatisfy(\.isHexDigit)
    }
}

private extension CharacterSet {
    static var ed2kFileNameAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "|")
        return allowed
    }
}
