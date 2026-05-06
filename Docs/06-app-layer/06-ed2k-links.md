# ED2KFileLink — Manejo de Enlaces eD2k

`MacMuleCore/Sources/MacMuleCore/ED2KLink.swift` (152 líneas)

## ED2KFileLink

```swift
public struct ED2KFileLink: Codable, Equatable, Hashable, Sendable {
    public let fileName: String
    public let sizeInBytes: UInt64
    public let hash: String                    // hash MD4 (32 chars hex)
    public let rootHash: String?              // hash AICH root (opcional)
    public let partHashes: [String]           // hashes de partes (opcional)
}
```

## Formato de Enlace

```
ed2k://|file|<fileName>|<sizeInBytes>|<hash>|[p=<partHashes>]|[h=<rootHash>]|/
```

Ejemplo:
```
ed2k://|file|ejemplo.avi|734003200|a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6|p=hash1:hash2:hash3|h=rootHash|/
```

## ED2KLinkParser

```swift
public enum ED2KLinkParser {
    public static func parseFileLink(_ rawLink: String) throws -> ED2KFileLink
}
```

### Parseo

1. Verifica prefijo `ed2k://`
2. Divide por `|`
3. Valida kind = "file"
4. Extrae fileName (con percent-decoding), size, hash
5. Extrae partHashes (`p=`) y rootHash (`h=`) si existen

### canonicalURL

```swift
public var canonicalURL: String {
    // genera URL completa con percent-encoding del nombre
}
```

## ED2KLinkParseError

```swift
public enum ED2KLinkParseError: Error, Equatable, LocalizedError {
    case invalidScheme
    case unsupportedLinkKind(String)
    case missingField(String)
    case invalidSize(String)
    case invalidHash(String)
}
```

## Integración con URL Scheme

MacMule registra el esquema `ed2k://`:

```swift
// MacMuleStore
func handleOpenURL(_ url: URL) {
    guard url.scheme?.lowercased() == "ed2k" else { return }
    enqueueED2KLinkString(url.absoluteString)
}
```

### Pasteboard (Cmd+Shift+V)

```swift
func pasteED2KLink() {
    let raw = NSPasteboard.general.string(forType: .string) ?? ""
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.lowercased().hasPrefix("ed2k://") else { return }
    enqueueED2KLinkString(trimmed)
}
```

## CharacterSet

```swift
static var ed2kFileNameAllowed: CharacterSet {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "|")
    return allowed
}
```

## Referencias

- [MacMuleStore](01-store.md) — addED2KLink y pasteED2KLink
- [Daemon Client](05-daemon-client.md) — add_ed2k_link RPC
- [Peer Download Flow](../07-data-flow/03-peer-download-flow.md) — uso en core
