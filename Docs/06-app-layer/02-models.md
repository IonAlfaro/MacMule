# MacMuleModels — Modelos de UI

`MacMule/Models/MacMuleModels.swift` (455 líneas)

## MacMuleSection

10 secciones de la aplicación:

```swift
enum MacMuleSection: String, CaseIterable, Identifiable {
    case dashboard     // Home
    case search        // Search
    case downloads     // Downloads
    case uploads       // Uploads
    case shared        // Shared
    case kad           // Kad
    case network       // Servers
    case statistics    // Statistics
    case settings      // Settings
    case logs          // Logs
}
```

Cada sección tiene `title` y `systemImage` para SF Symbols.

## TransferItem

Modelo de descarga/subida:

```swift
struct TransferItem: Identifiable, Hashable {
    let id: UUID
    var fileName: String
    var kind: FileKind
    var sizeInBytes: Int64
    var completedBytes: Int64
    var downloadSpeedBytesPerSecond: Int64
    var uploadSpeedBytesPerSecond: Int64
    var sources: Int
    var availability: Int
    var status: TransferStatus
    var ed2kHash: String
    var chunks: [ChunkState]  // 54 chunks para visualización
}
```

Propiedades computadas: `progress`, `sizeText`, `completedText`, `downloadSpeedText`, `estimatedTimeRemainingText`.

## TransferStatus

```swift
enum TransferStatus: String, CaseIterable, Hashable {
    case queued
    case downloading
    case paused
    case verifying
    case completed
    case failed
}
```

## SearchResult

```swift
struct SearchResult: Identifiable, Hashable {
    var fileName: String
    var kind: FileKind
    var sizeInBytes: Int64
    var sources: Int
    var availability: Int
    var network: String        // "eD2k" o "Kad"
    var ed2kHash: String
    var sourceClientID: UInt32?
    var sourceClientPort: UInt16?
}
```

## FileKind

```swift
enum FileKind: String, CaseIterable, Hashable {
    case video       // .avi .m4v .mkv .mov .mp4 .webm
    case audio       // .aac .aiff .flac .m4a .mp3 .ogg .wav
    case archive     // .7z .bz2 .dmg .gz .iso .rar .tar .xz .zip
    case document    // .doc .docx .epub .md .numbers .pages .pdf .rtf .txt .xls .xlsx
    case application // .app .ipa .pkg
    case other       // default
}
```

## NetworkSummary

```swift
struct NetworkSummary: Hashable {
    var isConnected: Bool
    var statusText: String
    var downloadSpeedBytesPerSecond: Int64
    var highID: Bool
    var kadNodes: Int
    var tcpPort: Int
    var udpPort: Int
}
```

## ServerSnapshot

```swift
struct ServerSnapshot: Identifiable, Hashable {
    var name: String
    var address: String              // "host:port"
    var users: Int
    var files: Int
    var pingMilliseconds: Int
    var health: ServerHealth         // .connected, .available, .unavailable
    var isPreferred: Bool
}
```

## CategoryItem, StatMetric, SourceDetail, ChunkState

| Tipo | Propósito |
|------|-----------|
| `CategoryItem` | Categorías de descarga con título y color |
| `StatMetric` | Métricas para statistics (title, value, systemImage) |
| `SourceDetail` | Detalles de fuente/peer: clientName, ipAddress, queueRank, score |
| `SourceState` | Estados: connecting, onQueue, downloading, noNeededParts, etc. |
| `ChunkState` | missing, queued, active, complete, corrupt |
| `KadNode` | Nodo Kad con nodeID, ip, puertos, distancia |
| `KadBucketStat` | Estadísticas de bucket: depth, count, maxSize, fullness |
| `KadSearchSummary` | Búsqueda Kad activa: type, results, nodesQueried |
| `SharedFile` | Archivo compartido: fileName, kind, size, requests |

## DownloadSortOrder

```swift
enum DownloadSortOrder: String, CaseIterable, Identifiable {
    case dateAdded    // calendar
    case name         // textformat.abc
    case progress     // arrow.down.circle
    case speed        // speedometer
    case size         // scalemass
    case sources      // person.2
}
```

## SearchMethod

```swift
enum SearchMethod: String, CaseIterable {
    case server = "Server"
    case kad = "Kad"
}
```

## Referencias

- [MacMuleStore](01-store.md) — store central
- [Navigation](03-navigation.md) — ContentView
- [Views Overview](04-views-overview.md) — vistas que usan estos modelos
