# Flujo App → Daemon

## Comunicación App ↔ Daemon

La app (MacMule.app) se comunica con el daemon (`macmule-core-daemon`) mediante **JSON-RPC 2.0** sobre **Unix socket** (AF_UNIX, SOCK_STREAM).

```
┌─────────────────┐     JSON-RPC 2.0     ┌─────────────────────┐
│  MacMule.app    │ ◄──────────────────► │  macmule-core-daemon │
│  (SwiftUI)      │    Unix socket       │  (SwiftPM binary)   │
│                 │                      │                     │
│ DaemonClient    │                      │ CoreRPCHandler      │
│  └ JSON-RPC     │                      │  └ CoreService      │
└─────────────────┘                      └─────────────────────┘
```

## JSON-RPC 2.0

Request:
```json
{"id": 1, "method": "snapshot", "params": {}}
```

Response:
```json
{"id": 1, "result": {"snapshot": {...}}}
```

Delimitador: newline (`0x0A`).

## CoreRPCHandler

El daemon traduce cada método RPC a `MacMuleCoreService`:

| RPC Method | CoreService Call |
|------------|-----------------|
| `snapshot` | `service.currentSnapshot()` |
| `events_since` | `service.events(after:)` |
| `add_ed2k_link` | `service.addED2KLink(link)` |
| `search` | `service.search(query:)` |
| `pause` / `resume` | `service.setDownloadPaused(id:paused:)` |
| `remove` | `service.removeDownload(id:)` |
| `connect_server` | `service.connectToServer(host:port:)` |
| `disconnect_server` | `service.disconnect()` |
| `add_server` | `service.addServer(host:port:)` |
| `remove_server` | `service.removeServer(host:port:)` |
| `import_servers` | `service.importServers(addresses:)` |
| `kad_start` | `service.kadStart()` |
| `kad_stop` | `service.kadStop()` |
| `kad_bootstrap` | `service.kadBootstrap(host:port:)` |
| `kad_search_keyword` | `service.kadSearchKeyword(query:)` |
| `kad_search_sources` | `service.kadSearchSources(hash:)` |
| `scheduler_add_entry` | `service.schedulerAddEntry(...)` |
| `scheduler_remove_entry` | `service.schedulerRemoveEntry(id:)` |
| `set_config` | `service.setConfig(maxDL:maxUL:)` |
| `add_category` | `service.addCategory(title:color:)` |
| `remove_category` | `service.removeCategory(id:)` |

## Event Polling

La app sondea `events_since` cada 500ms–2s para obtener deltas:

```json
{"id": 2, "method": "events_since", "params": {"after": "42"}}
```

Response incluye `snapshot` completo + eventos desde la secuencia indicada.

## CoreSnapshot

```swift
struct CoreSnapshot: Codable {
    var transfers: [CoreTransfer]
    var searchResults: [CoreSearchResult]
    var servers: [CoreServer]
    var network: CoreNetworkSummary
    var kad: CoreKadState
    var transferPeers: [UUID: [CorePeerInfo]]
    var categories: [CoreCategory]
}
```

## Referencias

- [Daemon Client](../06-app-layer/05-daemon-client.md) — implementación del cliente
- [Daemon to Network](02-daemon-to-network.md) — red del daemon
- [Peer Download Flow](03-peer-download-flow.md) — descarga P2P
