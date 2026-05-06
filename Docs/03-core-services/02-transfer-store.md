# CoreTransferStore — Persistencia de Transferencias

**Archivo fuente:** `MacMuleCore/Sources/MacMuleCore/CoreTransferStore.swift` — 886 líneas

**Propósito:** `CoreTransferStore` gestiona la persistencia en disco de las transferencias en curso. Maneja archivos `.part` en `Temp/`, metadatos en sidecars JSON, verificación de hashes, promoción atómica a `Incoming/` y recuperación tras crash.

---

## Estructura de Directorios

```
~Library/Application Support/MacMule/
  |-- Temp/                    # Archivos .part y metadatos JSON
  |     |-- {UUID}.part        # Datos parciales del archivo
  |     |-- {UUID}.json        # Metadatos (chunkMap, bookmarks)
  |-- Incoming/                # Archivos completados
  |-- Servers.json             # Lista de servidores
  |-- Identity.json            # Client user hash
  |-- ResumeCheckpoint.json    # Estado para recuperación
  |-- Runtime.lock             # Marcador de shutdown limpio
  |-- ServerBootstrap.json     # Seed version
```

---

## CoreTransferData

`CoreTransferRecord` (`CoreTransferStore.swift:193-261`) encapsula todos los metadatos de una transferencia:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `transfer` | `CoreTransfer` | fileName, size, ed2kHash, status, etc. |
| `partFileName` | `String` | Nombre del archivo .part |
| `completedFileName` | `String?` | Nombre tras promoción exitosa |
| `verifiedHash` | `String?` | Hash MD4 completo verificado |
| `verifiedPartHashes` | `[String?]` | Hashes de partes verificadas |
| `peerSourceBookmarks` | `[CorePeerSourceBookmark]` | Peers recordados |
| `peerInflightBookmarks` | `[CorePeerInflightBookmark]` | Rangos en vuelo |
| `peerChunkRetryBookmarks` | `[CorePeerChunkRetryBookmark]` | Cooldowns de reintento |
| `chunkMap` | `CoreChunkMap` | Mapa de chunks y rangos escritos |
| `createdAt` / `updatedAt` | `Date` | Timestamps |

---

## CoreChunk

`CoreTransferStore.swift:44-64`

Divide el archivo en chunks de **9.28 MB** (`CoreChunkMap.ed2kChunkSize = 9_728_000`), estándar de la red eD2k.

```swift
public struct CoreChunk {
    public var index: Int
    public var offset: UInt64
    public var length: UInt64
    public var completedBytes: UInt64
    public var status: CoreChunkStatus { ... }
}
```

### Chunk States

| Estado | Condición |
|--------|-----------|
| `.missing` | `completedBytes == 0` |
| `.partial` | `completedBytes > 0 && completedBytes < length` |
| `.complete` | `completedBytes >= length` |

---

## CoreByteRange

`CoreTransferStore.swift:26-38`

Representa un rango de bytes escritos en el archivo .part:

```swift
public struct CoreByteRange {
    public var offset: UInt64
    public var length: UInt64
    public var endOffset: UInt64 { offset + length }
}
```

Los rangos se mantienen **normalizados** (ordenados, sin solapamientos) via `CoreChunkMap.normalized()`.

---

## Operaciones Principales

### writeBlock

`CoreTransferStore.swift:616-652`

```swift
public func writeBlock(transferID: UUID, offset: UInt64, data: Data) throws -> CoreTransferRecord
```

1. Abre el archivo .part con `FileHandle(forWritingTo:)`
2. Busca al offset y escribe los datos
3. Limpia `verifiedPartHashes` solapados
4. Marca el rango como escrito en `chunkMap.markWritten(offset:length:)`
5. Actualiza `completedBytes`
6. Verifica hashes de partes completadas (`verifyCompletedPartHashes`)
7. Si todos los bytes están completos, verifica hash completo y promueve (`verifyAndPromoteCompletedPartFile`)
8. Guarda el record actualizado

### completeTransfer (Promoción Atómica)

`CoreTransferStore.swift:801-838`

Cuando `completedBytes >= sizeInBytes`:

1. Calcula `ED2KHash.hash(fileAt:)` del archivo .part completo
2. Compara contra `transfer.ed2kHash`
3. Si coincide: marca `.completed`, mueve el archivo .part a `Incoming/` con `FileManager.moveItem`
4. Si no coincide: marca `.failed`

La promoción es **atómica** — el archivo .part se mueve a `Incoming/` solo tras verificación exitosa.

### failTransfer

No hay un método explícito `failTransfer`. El fallo se produce por:
- **Hash mismatch** en `verifyCompletedPartHashes` o `verifyAndPromoteCompletedPartFile`
- El transfer se marca como `.failed` y el chunk corrupto se limpia para re-descarga

### Sidecar JSON

Cada transferencia tiene un archivo JSON en `Temp/{UUID}.json` que persiste el estado completo:

```json
{
    "transfer": { ... },
    "chunkMap": { "fileSizeInBytes": ..., "chunkSizeInBytes": ..., "writtenRanges": [...] },
    "peerSourceBookmarks": [...],
    "peerInflightBookmarks": [...],
    "peerChunkRetryBookmarks": [...]
}
```

### Resume Checkpoint

`CoreResumeCheckpoint` (`CoreTransferStore.swift:376-393`) es un archivo atómico `ResumeCheckpoint.json`:

```swift
public struct CoreResumeCheckpoint {
    public var activeTransferIDs: [UUID]
    public var activeSearchQuery: String?
    public var serverConfiguration: CoreResumeServerConfiguration?
    public var updatedAt: Date
}
```

Se actualiza en cada cambio de estado de transferencia y al modificar la conexión.

### Runtime Lock

`CoreTransferStore.swift:574-585`

```swift
@discardableResult
public func activateRuntimeLock() throws -> Bool
public func clearRuntimeLock() throws
```

- `activateRuntimeLock()` crea `Runtime.lock`; retorna `true` si ya existía (crash previo)
- `clearRuntimeLock()` elimina el lock en `deinit`
- Si al iniciar el lock existe, `MacMuleCoreService` ejecuta `normalizedCrashRecoveredSnapshot`

---

## Hash Verification

### Chunk individual

`CoreTransferStore.swift:765-799`

Cuando un chunk alcanza `.complete`:

```swift
let chunkData = try readPartData(for: id, offset: chunk.offset, length: chunk.length)
let actualHash = ED2KHash.hash(data: chunkData)
let expectedHash = transfer.partHashes[chunk.index]
guard actualHash == expectedHash else { ... status = .failed }
```

### Archivo completo

`CoreTransferStore.swift:801-812`

```swift
let actualHash = try ED2KHash.hash(fileAt: partFileURL(for: id))
if actualHash != transfer.ed2kHash { status = .failed }
```

---

## restoreFromPersistence

`CoreTransferStore.swift:482-499`

```swift
public func loadSnapshot() throws -> CoreSnapshot
```

1. Escanea `Temp/` en busca de archivos `.json`
2. Carga cada `CoreTransferRecord`
3. Ordena por `updatedAt` descendente
4. Carga `Servers.json`
5. Retorna `CoreSnapshot` con transfers y servidores

---

## Referencias

- [MacMuleCoreService](01-core-service.md) — orquestador que usa CoreTransferStore
- [Visión General de MacMule](../01-architecture/01-overview.md) — arquitectura general
- [ED2KHash](../02-protocols/ed2k-hash.md) — algoritmo de hash MD4
