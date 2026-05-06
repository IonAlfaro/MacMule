# CoreUploadQueue — Cola de Subidas

**Archivo fuente:** `MacMuleCore/Sources/MacMuleCore/CoreUploadQueue.swift` — 262 líneas

**Propósito:** `CoreUploadQueue` gestiona las subidas activas a peers de la red eD2k siguiendo el modelo de colas de eMule. Controla cuántos peers pueden descargar simultáneamente, quién espera turno y la priorización por score.

---

## CoreUploadSlot

`CoreUploadQueue.swift:3-50`

Representa una subida activa a un peer:

```swift
public struct CoreUploadSlot {
    public var clientID: KadUInt128
    public var clientIP: String
    public var clientPort: UInt16
    public var fileName: String
    public var fileHash: Data
    public var fileSize: UInt64
    public var uploadedBytes: UInt64
    public var uploadSpeed: UInt64
    public var requestedChunks: Int
    public var completedChunks: Int
    public var startedAt: Date
    public var lastActivity: Date
    public var queueRank: UInt32
    public var score: Double
}
```

Cada slot activo corresponde a un peer que está recibiendo datos de nuestra máquina.

---

## CoreWaitingClient

`CoreUploadQueue.swift:52-84`

Peers esperando su turno para descargar:

```swift
public struct CoreWaitingClient {
    public var clientID: KadUInt128
    public var clientIP: String
    public var clientPort: UInt16
    public var fileName: String
    public var fileHash: Data
    public var queueRank: UInt32
    public var score: Double
    public var waitStartTime: Date
    public var retryCount: Int
}
```

---

## Score-Based Priority

`CoreUploadQueue.swift:140-143`

Cuando se selecciona el siguiente cliente para promoción, se ordena por **score descendente** y luego por **tiempo de espera ascendente**:

```swift
let sorted = waitingClients.values.sorted { a, b in
    if abs(a.score - b.score) > 0.01 { return a.score > b.score }
    return a.waitStartTime < b.waitStartTime
}
```

Un score mas alto da prioridad. El score inicial es `1.0` y se reduce a `0.5` en reintentos tras fallo.

---

## maxActiveSlots

`CoreUploadQueue.swift:95`

```swift
public var maxActiveSlots: Int = 5
```

Por defecto hay **5 slots activos**. Se puede modificar en runtime. `acceptNextClient()` no promueve si `activeUploads.count >= maxActiveSlots`.

---

## Operaciones del Ciclo de Vida

### addClientToWaiting

`CoreUploadQueue.swift:111-132`

Agrega un peer a la lista de espera.

### acceptNextClient

`CoreUploadQueue.swift:134-159`

Promueve el mejor cliente en espera a slot activo:

1. Verifica que haya espacio (`activeUploads.count < maxActiveSlots`)
2. Ordena waitingClients por score + tiempo de espera
3. Remueve el mejor de la waiting list
4. Crea un `CoreUploadSlot` y lo inserta en `activeUploads`

### completeUpload / failUpload

`CoreUploadQueue.swift:161-185`

- `completeUpload(clientID:)`: elimina slot, incrementa `successfulUploads`
- `failUpload(clientID:)`: elimina slot, lo regresa a waiting con `score * 0.5`

En `failUpload`, el peer vuelve a la cola de espera con score reducido a la mitad para priorizar a otros.

### recordBytes

`CoreUploadQueue.swift:187-196`

Acumula bytes subidos en el slot y en `totalUploadedBytes`, actualiza `lastActivity`.

### updateSpeeds

`CoreUploadQueue.swift:251-261`

Recalcula `uploadSpeed` para cada slot activo como `uploadedBytes / elapsed` desde `lastActivity`.

### aggregateUploadSpeed

`CoreUploadQueue.swift:245-249`

```swift
public var aggregateUploadSpeed: UInt64 {
    activeUploads.values.reduce(0) { $0 + $1.uploadSpeed }
}
```

Velocidad total de subida sumando todos los slots activos.

---

## Referencias

- [MacMuleCoreService](01-core-service.md) — orquestador que gestiona las subidas
- [CoreSharedFileList](04-shared-files.md) — fuente de archivos para subir
- [Vision General de MacMule](../01-architecture/01-overview.md) — arquitectura general
