# CoreSharedFileList — Archivos Compartidos

**Archivo fuente:** `MacMuleCore/Sources/MacMuleCore/CoreSharedFileList.swift` — 288 líneas

**Propósito:** `CoreSharedFileList` gestiona la lista de archivos compartidos localmente. Escanea carpetas configuradas, calcula hashes eD2k incrementales y publica la lista al servidor conectado.

---

## SharedFileEntry

`CoreSharedFileList.swift:5-37`

```swift
public struct SharedFileEntry {
    public var filePath: String
    public var fileName: String
    public var fileSize: UInt64
    public var ed2kHash: Data
    public var partHashes: [Data]
    public var requests: Int
    public var uploadedBytes: UInt64
    public var sharedAt: Date
    public var lastRequestedAt: Date?
}
```

Cada entrada representa un archivo compartido con su hash ED2K completo, hashes de partes individuales y estadisticas de peticiones/subidas.

---

## Gestión de Carpetas

### addFolder / removeFolder

`CoreSharedFileList.swift:47-53`

```swift
public func addSharedDirectory(_ path: String)
public func removeSharedDirectory(_ path: String)
```

Gestionan el conjunto `sharedDirectories: Set<String>`. Las carpetas se almacenan como paths absolutos.

---

## scan

`CoreSharedFileList.swift:55-92`

```swift
public func scanDirectories() async throws -> [SharedFileEntry]
```

1. Itera sobre `sharedDirectories`
2. Usa `FileManager.default.enumerator` para recorrer recursivamente cada carpeta
3. Filtra por archivos regulares (skips hidden files y packages)
4. Calcula el hash eD2k de cada archivo via `computeHash(for:)`
5. Crea `SharedFileEntry` y la inserta en el diccionario `sharedFiles[ed2kHash]`

---

## eD2k Hashing Incremental

`CoreSharedFileList.swift:128-204`

### FileHasher

Implementación privada de hash MD4 incremental para calcular el hash eD2k de archivos:

```
MD4(chunk[0]) + MD4(chunk[1]) + ... + MD4(chunk[N-1])
     +--> MD4 de la concatenacion de hashes parciales (si hay > 1 parte)
```

Detalles:

- **Chunk size:** 9.728.000 bytes (estandar eD2k)
- **Algoritmo:** MD4 puro implementado manualmente (funciones `md4f`, `md4g`, `md4h`, `rotateLeft`)
- El hash del archivo completo es:
  - Si el archivo cabe en un solo chunk: `MD4(datos)`
  - Si tiene multiples chunks: `MD4(partHash[0] + partHash[1] + ... + partHash[N-1])`

### Part Hashes

```swift
mutating func update(_ data: Data) // Procesa datos en bloques de 9.728.000 bytes
mutating func finalize() -> Data   // Retorna el hash MD4 final de 16 bytes
```

---

## Operaciones Principales

### allSharedFiles

`CoreSharedFileList.swift:94-96`

```swift
public func allSharedFiles() -> [SharedFileEntry]
```

Retorna todos los archivos compartidos ordenados alfabeticamente por nombre. Usado por `MacMuleCoreService` para enviar `offerFiles` al servidor.

### publishToServer

La publicacion al servidor ocurre en `MacMuleCoreService`, no en esta clase. En `applyServerSessionEventLocked` (`CoreService.swift:1734-1744`), tras login exitoso:

```swift
if files.isEmpty {
    _ = postLoginConnection.sendEmptyOfferFiles()
} else {
    _ = postLoginConnection.sendOfferFiles(fileHashes: files.map(\.ed2kHash))
}
```

### removeFile

`CoreSharedFileList.swift:120-122`

```swift
public func removeFile(fileHash: Data)
```

Elimina un archivo de la lista compartida por su hash.

### recordRequest / recordUpload

`CoreSharedFileList.swift:106-114`

```swift
public func recordRequest(fileHash: Data, bytes: UInt64)
```

Incrementa `requests` y `uploadedBytes` para el archivo. Llamado desde `applyIncomingPeerSessionEventLocked` cuando un peer solicita una parte.

---

## Referencias

- [MacMuleCoreService](01-core-service.md) — orquestador que usa CoreSharedFileList
- [CoreUploadQueue](03-upload-queue.md) — peers descargando archivos compartidos
- [ED2KHash](../02-protocols/ed2k-hash.md) — algoritmo de hash MD4
- [Vision General de MacMule](../01-architecture/01-overview.md) — arquitectura general
