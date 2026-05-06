# MacMuleCoreService — El Orquestador Central

**Archivo fuente:** `MacMuleCore/Sources/MacMuleCore/CoreService.swift` — 4293 líneas

**Propósito:** `MacMuleCoreService` es la clase más grande del proyecto y actúa como el orquestador central de todo el motor P2P. Coordina conexiones a servidores eD2k, transferencias peer-to-peer, búsquedas, la red Kad, el servidor web, el scheduler, archivos compartidos, cola de subidas y rate limiting. Todo el estado mutable vive dentro de un `NSLock` y se expone al exterior mediante snapshots inmutables (`CoreSnapshot`) y un sistema de eventos (`CoreEvent`).

---

## Inicialización

```swift
public init(
    snapshot: CoreSnapshot = .empty,
    transferStore: CoreTransferStore? = nil,
    networkLogHandler: (@Sendable (String) -> Void)? = nil,
    serverTransportFactory: ..., peerTransportFactory: ...,
    peerListenerTransportFactory: ..., peerPortMapper: ...
)
```

El initializer (`CoreService.swift:263-350`) acepta inyección de dependencias. Durante `init`:

1. **Carga o crea el `clientUserHash`** — identidad única de 16 bytes persistida en `Identity.json`.
2. **Restaura el snapshot** — desde `CoreSnapshot` persistido en disco con normalización de servidores y estados.
3. **Detección de crash** — si `Runtime.lock` existe al iniciar, recupera transfers vía `CoreResumeCheckpoint` y fuerza estado `.queued`.
4. **Restaura estado de peers** — carga bookmarks desde sidecars JSON.
5. **Inicializa módulos Tier 0:** `CoreUploadQueue`, `CoreSharedFileList`, `CoreCreditsList`, `CoreIPFilter`, `CoreCorruptionBlackBox`, `CoreRarityScheduler`, `CoreKnownFileList`, `CoreScheduler`.

---

## Máquina de Estados

```
offline -> connecting -> connected (HighID / LowID) -> disconnected -> offline
               |                                            ^
               +----> failed -------------------------------+
```

Los eventos se procesan en `applyServerConnectionEvent(_:endpoint:generation:)` (`CoreService.swift:1548-1757`):

| Evento | Acción |
|--------|--------|
| `.stateChanged(.connecting)` | Estado "Connecting to..." |
| `.stateChanged(.connected)` | Conexión TCP establecida |
| `.stateChanged(.disconnected)` | Limpia sesión, reconexión o failover |
| `.stateChanged(.failed)` | Failover inmediato |
| `.loginFailed` | Failover o reconexión |
| `.sessionEvent(.idChange)` | Login aceptado, determina HighID/LowID |
| `.sessionEvent(.serverMessage)` | Failover si contiene "too old" |
| `.sessionEvent(.foundSources)` | Fuentes recibidas, inicia descargas |

### HighID vs LowID

Cuando el servidor acepta el login, envía `idChange` con `clientID` y `highID`. Si `highID == true`, el cliente es accesible directamente. Si es `false` (LowID), las conexiones entrantes pasan por callbacks del servidor.

---

## Reconexión Automática (scheduleReconnect)

`CoreService.swift:1532-1546`

```swift
private func scheduleReconnect() {
    let config = withLock { reconnectConfiguration }
    let workItem = DispatchWorkItem { [weak self] in
        _ = self?.connectToServer(config)
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: workItem)
}
```

- Espera **15 segundos** antes de reintentar
- Usa la última `reconnectConfiguration` exitosa
- Se cancela en `disconnectServer()` si el usuario desconecta manualmente

---

## Failover entre Servidores

`CoreService.swift:1942-1969`

1. **Marca el servidor actual como `.unavailable`**
2. **Busca el siguiente servidor disponible** — orden circular, preferidos primero
3. **Conecta al nuevo** vía `failoverToServer(_:)`

También se activa por mensajes "too old" del servidor:

```swift
private func shouldFailoverForServerMessage(_ serverMessage: String) -> Bool {
    let normalized = serverMessage.lowercased()
    return normalized.contains("too old")
        && (normalized.contains("edonkey") || normalized.contains("client") || normalized.contains("id"))
}
```

---

## PeerDownloadPlan

`CoreService.swift:24-29`

```swift
private struct PeerDownloadPlan {
    var transferID: UUID
    var fileHash: Data
    var endpoint: ED2KPeerEndpoint
    var range: ED2KPartRange
}
```

Construido en `makePeerDownloadPlanLocked(transfer:)` (`CoreService.swift:2914-2947`):

1. Verifica límite `maxConcurrentPeerConnectionsPerTransfer` (2 conexiones)
2. Busca endpoint en `peerSourceQueues` disponible (sin cooldown)
3. Reserva rango via `reserveNextPeerRequestRangeLocked` considerando:
   - Rangos completados (`CoreChunkMap.writtenRanges`)
   - Rangos in-flight de otras conexiones
   - Rareza via `CoreRarityScheduler`
   - Chunk retry cooldowns (backoff exponencial)
   - Block size de 256 KB (`peerRequestBlockSize`)

---

## GetSources Queue

`CoreService.swift:2363-2534`

Cola de solicitudes de fuentes al servidor, estilo eMule:

| Propiedad | Valor |
|-----------|-------|
| `maxSourceLookupRequestsPerPass` | 15 |
| `emptySourceLookupRetryInterval` | 45s |
| `normalSourceLookupRetryInterval` | 10 min |
| `sourceLookupMaintenanceInterval` | 30s |

Flujo: `requestSourcesIfPossible()` -> `flushQueuedSourceLookupsIfPossible()` -> `performSourceLookupMaintenance()`.

### Callbacks LowID

Cuando un peer tiene LowID, el servidor actúa como intermediario. `ServerCallbackRequest` almacena `transferID`, `fileHash`, `sourceClientID`, `sourceClientPort`. `queueServerCallbackRequestsLocked()` filtra y encola. El servidor responde con `callbackRequested` para crear un `PeerDownloadPlan`.

---

## Source Exchange v2/v4

`CoreService.swift:2791-2843`

Al recibir `ED2KPeerSourceExchangeAnswer`:

1. Verifica hash del archivo
2. Convierte LowIDs a callbacks, HighIDs a `peerSourceQueues`
3. Actualiza `sources` y `availability` en el transfer
4. Dispara `startPeerDownloadsIfPossible`

---

## Part HashSet Verification

`CoreService.swift:3791-3844`

Al recibir `ED2KPartHashSet`:

1. Verifica `fileHash` coincida con el transfer
2. Verifica cantidad de part hashes contra `expectedPartCount`
3. Guarda partHashes si no se tenían
4. Reconciliación via `reconcilePersistedTransferLocked`

Los hashes de partes individuales también se verifican en `CoreTransferStore.verifyCompletedPartHashes` al completar chunks.

---

## Rate Limit Tracking

`CoreService.swift:71-180`

### ByteRateTracker
- Ventana móvil de **10 segundos**
- Idle timeout de **3 segundos**
- Rate mínimo de **1 segundo**
- Velocidad = `bytes totales / tiempo transcurrido`

### DatarateAverager
- Promedio móvil de muestras de velocidad
- Mínimo 0.5s entre muestras
- Requiere 2+ muestras

Trackeo por `PeerSpeedKey[transferID, endpoint]` y `directTransferSpeedTrackers[transferID]`.

---

## Chunk Retry Cooldowns

`CoreService.swift:3702-3761`

Cuando se pierde conexión en un rango específico:

- `failureCount` para ese rango
- Cooldown exponencial: `base 15s * 2^(failureCount - 1)`
- Máximo: 120s
- Se limpia al descargar exitosamente

---

## Source Cooldowns

`CoreService.swift:3094-3105`

Por endpoint que falla:

- `peerSourceFailures[transferID][endpoint]` cuenta fallos consecutivos
- `peerSourceCooldowns[transferID][endpoint] = Date() + cooldownInterval`
- `reorderPeerSourceQueueLocked()` prioriza sin cooldown y con menos fallos

---

## Búsquedas Pendientes

`CoreService.swift:1448-1502`

`search(query:)` guarda `activeSearchQuery`. Si no hay conexión, auto-conecta al servidor preferido. Tras login exitoso, re-ejecuta automáticamente. Persiste en `CoreResumeCheckpoint`.

---

## UPnP / NAT-PMP

`CoreService.swift:2090-2106`

```swift
peerPortMapper.ensureMappings(tcpPort: tcpPort, udpPort: udpPort) { result in ... }
```

Usa `SequentialPeerPortMapper` probando UPnP (`UPnPPortMapper`) y luego NAT-PMP (`NATPMPPortMapper`).

---

## Persistencia

| Mecanismo | Archivo | Propósito |
|-----------|---------|-----------|
| Snapshot | `loadSnapshot()` | Estado completo serializado |
| Sidecar JSON | `{UUID}.json` en Temp/ | chunkMap, bookmarks, retry states |
| Resume Checkpoint | `ResumeCheckpoint.json` | Transfers activos, search, server config |
| Runtime Lock | `Runtime.lock` | Clean shutdown detection |
| Servidores | `Servers.json` | Lista de servidores |
| Bootstrap | `ServerBootstrap.json` | Seed version tracking |

---

## Referencias

- [CoreTransferStore](02-transfer-store.md) — persistencia de transfers, chunk map, sidecars
- [CoreUploadQueue](03-upload-queue.md) — cola de subidas activas
- [CoreSharedFileList](04-shared-files.md) — archivos compartidos
- [CoreScheduler](05-scheduler.md) — automatización por tiempo
- [CoreWebServer](06-web-server.md) — interfaz web embebida
- [Visión General de MacMule](../01-architecture/01-overview.md) — arquitectura general
