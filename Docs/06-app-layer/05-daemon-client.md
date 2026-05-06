# DaemonMacMuleCoreClient — Conexión App ↔ Daemon

`MacMule/Core/DaemonMacMuleCoreClient.swift` (680 líneas)

## DaemonMacMuleCoreClient

Implementación de `MacMuleCoreClient` que se comunica con `macmule-core-daemon` vía **Unix socket**.

## Unix Socket RPC

Usa `UnixSocketRPCClient` interno:

```
AF_UNIX, SOCK_STREAM → socket()
↓
connect() al socket path
↓
write() → request JSON-RPC + newline (0x0A)
↓
read() → response JSON-RPC hasta newline
```

### Timeouts

- `SO_RCVTIMEO` y `SO_SNDTIMEO`: 8 segundos
- Previene bloqueo indefinido del thread

### JSON-RPC

```json
{"id": 1, "method": "snapshot", "params": {}}
{"id": 1, "result": {"snapshot": {...}}}
```

Delimitador: newline `0x0A` entre request y response.

## MacMuleDaemonLauncher

`MacMule/Core/MacMuleDaemonLauncher.swift` — Lanza el binario `macmule-core-daemon` desde `MacOS/` dentro del bundle:

```swift
static func launchBundledDaemonAsync(
    forceFresh: Bool,
    storageDirectory: URL?,
    incomingDirectory: URL?,
    tempDirectory: URL?
) async -> MacMuleDaemonSession?
```

## Restart Core

```swift
func restartCore() async -> MacMuleSnapshot {
    daemonSession?.stop()
    daemonSession = nil
    // lanza nuevo daemon
    guard let session = await MacMuleDaemonLauncher.launchBundledDaemonAsync(...) else {
        return .empty
    }
    socketPath = session.socketPath
    daemonSession = session
    return await currentSnapshot()
}
```

## JSONRPCRequest/Response

```swift
struct JSONRPCRequest: Codable {
    let id: Int
    let method: String
    let params: [String: String]?
}

struct JSONRPCResponse: Codable {
    let id: Int?
    let result: JSONRPCResult?
    let error: JSONRPCError?
}

struct JSONRPCResult: Codable {
    let snapshot: CoreSnapshot?
    let eventBatch: CoreEventBatch?
}
```

## Métodos RPC

| Método App | RPC Method |
|------------|------------|
| `currentSnapshot()` | `snapshot` |
| `events(after:)` | `events_since` |
| `search(query:)` | `search` |
| `addED2KLink(_:)` | `add_ed2k_link` |
| `setDownloadPaused(id:paused:)` | `pause` / `resume` |
| `removeDownload(id:)` | `remove` |
| `setConnection(enabled:)` | `connect_server` / `disconnect_server` |
| `addServer(host:port:)` | `add_server` |
| `removeServer(host:port:)` | `remove_server` |
| `importServers(servers:)` | `import_servers` |
| `kadStart()` | `kad_start` |
| `kadStop()` | `kad_stop` |
| `kadBootstrap(host:port:)` | `kad_bootstrap` |
| `kadSearchKeyword(query:)` | `kad_search_keyword` |
| `kadSearchSources(hash:)` | `kad_search_sources` |
| `setConfig(...)` | `set_config` |
| `restartCore()` | stop + relaunch |

## ServerMetParser

`MacMule/Core/ServerMetParser.swift` — Parseo de listas server.met (formato binario eD2k):

```swift
static func parse(_ data: Data) -> [(host: String, port: UInt16)]
```

## Referencias

- [MacMuleStore](01-store.md) — store central
- [App to Daemon Data Flow](../07-data-flow/01-app-to-daemon.md) — flujo de datos
- [ED2K Links](06-ed2k-links.md) — manejo de enlaces
