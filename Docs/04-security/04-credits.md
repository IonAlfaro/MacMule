# CoreCreditsList — Sistema de Créditos

`MacMuleCore/Sources/MacMuleCore/CoreCreditsList.swift` (125 líneas)

## Descripción

Sistema de créditos estilo eMule: prioriza peers que han subido datos a cambio de descargas. Cada peer tiene un `CreditRecord` con su historial de subida/descarga. Los peers con mayor score obtienen mejor posición en colas de descarga.

## CreditRecord

```swift
public struct CreditRecord: Equatable, Sendable, Codable {
    public var userHash: Data
    public var uploadedBytes: UInt64
    public var downloadedBytes: UInt64
    public var lastSeen: Date
    public var score: Double
}
```

### Cálculo de Score

```swift
let ratio = uploadedBytes / downloadedBytes
if uploadedBytes == 0        → score = 1.0
else if ratio >= 1.0         → score = 2.0 + min(ratio - 1.0, 10.0)
else                         → score = ratio
```

Peer que ha subido más de lo que descargó → score > 2 (máximo 12). Nuevos peers → score = 1.0.

## CoreCreditsList

```swift
public final class CoreCreditsList: @unchecked Sendable {
    public func getCredit(userHash: Data) -> CreditRecord
    public func addUploadBytes(_ bytes: UInt64, for userHash: Data)
    public func addDownloadBytes(_ bytes: UInt64, for userHash: Data)
    public func score(for userHash: Data) -> Double
    public func allCredits() -> [CreditRecord]  // ordenados por score descendente
    public func count() -> Int
}
```

## Persistencia

```swift
public func save(to url: URL) throws   // JSONEncoder → Data → url
public func load(from url: URL) throws  // url → Data → JSONDecoder
```

Los créditos se guardan en `Core/credits.json` dentro del directorio de almacenamiento del core.

## Thread Safety

Todo el acceso al diccionario `credits: [Data: CreditRecord]` está protegido con `NSLock`.

## Referencias

- [CoreSecureIdent](02-secure-ident.md) — identidad segura de peers
- [CoreIPFilter](01-ip-filter.md) — filtro de rangos IP
- [Peer Download Flow](../07-data-flow/03-peer-download-flow.md) — uso de score en colas
