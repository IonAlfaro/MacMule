# MacMuleStore — Store Central ObservableObject

`MacMule/Models/MacMuleStore.swift` (811 líneas)

## Descripción

Store central de la app. Es un `ObservableObject` `@MainActor` que maneja todo el estado de la UI, configuración persistida y comunicación con el core. Es la única fuente de verdad para las vistas.

## UI State

```swift
@Published var selectedSection: MacMuleSection?
@Published var selectedDownloadID: TransferItem.ID?
@Published var searchQuery: String
@Published var searchMethod: SearchMethod
@Published var searchFileKind: FileKind?
@Published var searchMinSizeKB: String
@Published var searchMaxSizeKB: String
@Published var searchExtensionFilter: String
@Published var ed2kLinkText: String
@Published private(set) var isSearching: Bool
@Published var downloadSortOrder: DownloadSortOrder
@Published private(set) var isAddingED2KLink: Bool
@Published private(set) var isRefreshing: Bool
@Published private(set) var isRestartingCore: Bool
@Published private(set) var ed2kLinkError: String?
```

## Settings (UserDefaults-backed)

| Propiedad | UserDefaults Key | Default |
|-----------|-----------------|---------|
| `downloadDirectory` | `"downloadDirectory"` | `~/Downloads/MacMule` |
| `tempDirectory` | `"tempDirectory"` | `~/Library/Application Support/MacMule/Core/Temp` |
| `maxDownloadKilobytes` | `"maxDownloadKilobytes"` | `4096` |
| `maxUploadKilobytes` | `"maxUploadKilobytes"` | `512` |
| `autoConnect` | `"autoConnect"` | `true` |
| `shareCompletedDownloads` | `"shareCompletedDownloads"` | `false` |
| `nickname` | `"nickname"` | `"MacMule"` |
| `tcpPort` | `"tcpPort"` | `"4662"` |
| `udpPort` | `"udpPort"` | `"4672"` |
| `maxConnections` | `"maxConnections"` | `"500"` |
| `maxSourcesPerFile` | `"maxSourcesPerFile"` | `"50"` |
| `enableKad` | `"enableKad"` | `true` |
| `enableUPnP` | `"enableUPnP"` | `true` |
| `autoRemoveCompleted` | `"autoRemoveCompleted"` | `false` |
| `obfuscationEnabled` | `"obfuscationEnabled"` | `false` |
| `secureIdentEnabled` | `"secureIdentEnabled"` | `false` |

## Core State

```swift
@Published private(set) var downloads: [TransferItem]
@Published private(set) var uploads: [TransferItem]
@Published private(set) var searchResults: [SearchResult]
@Published private(set) var servers: [ServerSnapshot]
@Published private(set) var sharedFiles: [SharedFile]
@Published private(set) var statistics: [StatMetric]
@Published private(set) var network: NetworkSummary
@Published private(set) var kad: KadSummary
@Published private(set) var kadNodes: [KadNode]
@Published private(set) var kadBucketStats: [KadBucketStat]
@Published private(set) var kadActiveSearches: [KadSearchSummary]
@Published private(set) var transferPeers: [UUID: [SourceDetail]]
@Published private(set) var categories: [CategoryItem]
```

## Core Runtime

```swift
@Published private(set) var coreRuntimeStatus: MacMuleCoreRuntimeStatus
@Published private(set) var coreRuntimeLogs: [MacMuleCoreLogEntry]
```

## Speed Chart History

```swift
@Published private(set) var downloadSpeedHistory: [Double]  // 60 samples, normalized 0-1
@Published private(set) var uploadSpeedHistory: [Double]
```

Caps: 10 MB/s descarga, 5 MB/s subida.

## Conexión al Core

`start()` determina el cliente:

1. `MACMULE_CORE_SOCKET` env → socket externo
2. Sino → `MacMuleDaemonLauncher.launchBundledDaemonAsync()`
3. Si no hay daemon → `EmptyMacMuleCoreClient`

## Event Polling

- 500ms si hay descargas activas
- 2s si no
- Usa `core.events(after:)`

## Métodos

| Método | Descripción |
|--------|-------------|
| `start()` | Inicializa conexión al core |
| `runSearch()` | Búsqueda server o Kad |
| `addED2KLink()` | Añade desde enlace ed2k:// |
| `toggleConnection()` | Conecta/desconecta |
| `refreshSnapshot()` | Refresca estado |
| `togglePause(downloadID:)` | Pausa/reanuda |
| `removeDownload(downloadID:)` | Elimina descarga |
| `addServer(host:port:)` | Añade servidor |
| `restartCore()` | Reinicia daemon |
| `kadStart()` / `kadStop()` | Control Kad |
| `handleOpenURL(_:)` | URLs ed2k:// |
| `pasteED2KLink()` | Portapapeles |

## Referencias

- [MacMuleModels](02-models.md)
- [Navigation](03-navigation.md)
- [Daemon Client](05-daemon-client.md)
- [ED2K Links](06-ed2k-links.md)
