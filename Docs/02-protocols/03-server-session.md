# Sesiones con Servidores eD2k

## Arquitectura

La conexión con servidores eD2k se divide en dos capas separables:

```
┌──────────────────────────────────────────────┐
│           ED2KServerTCPConnection              │
│  - Ciclo de vida connect/disconnect           │
│  - Timeout de conexión (30s)                  │
│  - Envío de comandos (search, getSources)      │
│  - Reenvío de eventos                         │
├──────────────────────┬───────────────────────┤
│  ED2KServerSession   │  ED2KServerTCPTransport│
│  - Login handshake   │  - NWConnection        │
│  - Decode de paquetes│  - Send/Receive        │
│  - Eventos           │  - Intercambiable      │
└──────────────────────┴───────────────────────┘
```

## ED2KServerTCPConnection

Archivo: `ED2KServerTCPConnection.swift`

### Estados

```swift
public enum ED2KServerTCPConnectionState {
    case connecting          // Iniciando conexión TCP
    case waiting(String)     // Esperando (DNS, path setup)
    case connected           // Conectado y login enviado
    case disconnected        // Desconectado
    case failed(String)      // Error irrecuperable
}
```

### Diagrama de estados

```
       ┌──────────┐
       │   init   │
       └────┬─────┘
            │ start()
            ▼
      ┌───────────┐
      │ connecting│ ← scheduleConnectionTimeout(30s)
      └─────┬─────┘
            │ NWConnection .ready
            ▼
       ┌─────────┐
       │ connected│ ← sendLogin()
       │          │ ← receiveNext()
       └────┬─────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌──────────┐ ┌────────┐
│disconnected│ │ failed │
└──────────┘ └────────┘
```

### Timeout de conexión

30 segundos por defecto. Si el transporte no alcanza `.ready` en ese tiempo:

```swift
private static let connectionTimeout: TimeInterval = 30
```

Se emite `stateChanged(.failed("Timed out connecting..."))` y se cancela.

### Transporte Intercambiable

`ED2KServerTCPTransport` es un protocolo que permite inyectar transportes alternativos (útiles para testing):

```swift
public protocol ED2KServerTCPTransport: AnyObject {
    var stateUpdateHandler: ((ED2KServerTCPTransportState) -> Void)? { get set }
    var receiveHandler: ((Data) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func send(_ data: Data, completion: @escaping (ED2KServerTCPTransportSendResult) -> Void)
    func receiveNext()
    func cancel()
}
```

**Implementación real**: `NetworkED2KServerTCPTransport` — usa `NWConnection(host:port:.tcp)`

### Eventos de conexión

```swift
public enum ED2KServerTCPConnectionEvent {
    case stateChanged(ED2KServerTCPConnectionState)
    case sessionEvent(ED2KServerSessionEvent)
    case loginSent
    case loginFailed(String)
    case searchSent(String)
    case searchFailed(query: String, message: String)
    case sourceLookupSent(String)
    case sourceLookupFailed(hash: String, message: String)
    case callbackRequestSent(UInt32)
    case callbackRequestFailed(UInt32, String)
    case receiveFailed(String)
}
```

## ED2KServerSession

Archivo: `ED2KServerSession.swift`

### Configuración

```swift
public struct ED2KServerSessionConfiguration {
    public var endpoint: ED2KServerEndpoint  // host:puerto del servidor
    public var userHash: Data                // hash único del usuario (16 bytes, MD4)
    public var clientID: UInt32              // ID asignado (0 si primer login)
    public var tcpPort: UInt16               // puerto TCP local (default 4662)
    public var nickname: String              // nombre visible del usuario
    public var protocolVersion: UInt32       // versión del protocolo (default 60)
    public var flags: UInt32                 // flags de capacidad
}
```

### Flags de Capacidad

```swift
public static let serverCapabilityZlib: UInt32 = 0x0001         // Compresión zlib
public static let serverCapabilityNewTags: UInt32 = 0x0008      // Tags nuevo formato
public static let serverCapabilityUnicode: UInt32 = 0x0010      // Soportar Unicode
public static let serverCapabilityLargeFiles: UInt32 = 0x0100   // Archivos >4GB
public static let serverCapabilitySupportCryptLayer: UInt32 = 0x0200
public static let serverCapabilityRequestCryptLayer: UInt32 = 0x0400
```

### Flujo de Login

```
Cliente                              Servidor
  │                                      │
  │──── loginRequest (0x01) ───────────► │
  │    userHash (16 bytes)               │
  │    clientID (UInt32 LE)              │
  │    tcpPort (UInt16 LE)               │
  │    tagCount (UInt32 LE)              │
  │    tags: ED2KTag[]                   │
  │      nick (0x01, string)             │
  │      version (0x11, uint32=60)       │
  │      flags (0x20, uint32)            │
  │      muleVersion (0xFB, uint32)      │
  │                                      │
  │◄─── idChange (0x40) ─────────────── │
  │    clientID (UInt32 LE)              │
  │    tcpFlags (UInt32, opcional)       │
  │    auxTCPPort (UInt32, opcional)     │
  │    serverReportedIP (UInt32, opc.)   │
  │    obfuscationTCPPort (UInt32, opc.) │
  │                                      │
  │◄─── serverIdent (0x41) ──────────── │
  │    serverHash (16 bytes)             │
  │    serverIP (4 bytes octets)         │
  │    serverPort (2 o 4 bytes)          │
```

### HighID vs LowID

```swift
public static func isHighID(_ clientID: UInt32) -> Bool {
    clientID >= 0x01000000
}
```

- **HighID** (≥ 0x01000000): el cliente es accesible directamente desde internet
- **LowID**: el cliente está detrás de NAT/firewall; necesita callbacks del servidor

### Eventos de Sesión

```swift
public enum ED2KServerSessionEvent {
    case outgoingLogin(ED2KPacket)
    case idChange(ED2KIDChange)
    case serverMessage(ED2KServerMessage)
    case serverStatus(ED2KServerStatus)
    case serverIdentity(ED2KServerIdentity)
    case serverList([ED2KServerEndpoint])
    case searchResults([ED2KSearchResult])
    case foundSources(ED2KFoundSources)
    case callbackRequested(ED2KPeerEndpoint)
    case callbackFailed
    case unhandledPacket(ED2KPacket)
}
```

### Métodos de Sesión

| Método | Propósito |
|--------|-----------|
| `loginPacket()` → `ED2KPacket` | Paquete de login (opcode 0x01) |
| `searchPacket(query:)` → `ED2KPacket` | Búsqueda por palabra clave |
| `offerFilesPacket(fileHashes:)` → `ED2KPacket` | Publicar archivos |
| `emptyOfferFilesPacket()` → `ED2KPacket` | Publicación vacía (keep-alive) |
| `sourceRequestPacket(fileHash:fileSize:)` → `ED2KPacket` | Solicitar fuentes |
| `callbackRequestPacket(clientID:)` → `ED2KPacket` | Solicitar callback |
| `receive(_ data:)` → `[ED2KServerSessionEvent]` | Procesar datos entrantes |

## ED2KIDChange

```swift
public struct ED2KIDChange {
    public var clientID: UInt32
    public var tcpFlags: UInt32?
    public var auxiliaryTCPPort: UInt32?
    public var serverReportedIP: UInt32?
    public var obfuscationTCPPort: UInt32?
    public var highID: Bool { ED2KClientID.isHighID(clientID) }
}
```

## ED2KServerMessage

```swift
public struct ED2KServerMessage {
    public var rawText: String
    public var lines: [String]  // dividido por saltos de línea
}
```

## ED2KSearchResult

```swift
public struct ED2KSearchResult {
    public var fileHash: Data         // hash MD4 del archivo (16 bytes)
    public var clientID: UInt32       // ID del peer que comparte
    public var clientPort: UInt16     // puerto TCP del peer
    public var tags: [ED2KTag]        // metadatos (nombre, tamaño, etc.)
}
```

## ED2KFoundSources

```swift
public struct ED2KFoundSources {
    public var fileHash: Data
    public var sources: [ED2KFoundSource]
}

public struct ED2KFoundSource {
    public var clientID: UInt32
    public var clientPort: UInt16
}
```

## Flujo Completo de Conexión

```
┌──────────────────────────────────────────────────────────┐
│ 1. ED2KServerTCPConnection(configuration:).start()       │
│    ├─ stateChanged(.connecting)                           │
│    └─ scheduleConnectionTimeout(30s)                      │
│                                                            │
│ 2. NetworkED2KServerTCPTransport.start(queue:)             │
│    └─ NWConnection(host:port:.tcp).start(queue:)          │
│                                                            │
│ 3. NWConnection.state → .ready                            │
│    ├─ stateChanged(.connected)                             │
│    ├─ sendLogin() → loginPacket.encoded()                  │
│    │   └─ loginSent / loginFailed evento                   │
│    └─ receiveNext() → receiveHandler(data:)                │
│                                                            │
│ 4. session.receive(data) → [ED2KServerSessionEvent]        │
│    ├─ .idChange → guardar clientID (High/Low)               │
│    ├─ .serverIdentity → datos del servidor                  │
│    ├─ .serverStatus → users/files                           │
│    ├─ .serverList → otros servidores                        │
│    └─ .serverMessage → mensaje de bienvenida                │
│                                                            │
│ 5. Comandos del usuario                                    │
│    ├─ sendSearch("query") → searchSent / searchResults     │
│    ├─ sendSourceLookup(hash,size) → foundSources           │
│    ├─ sendEmptyOfferFiles() → keep-alive                   │
│    └─ sendCallbackRequest(clientID) → callbackRequested    │
│                                                            │
│ 6. ED2KServerTCPConnection.cancel()                        │
│    └─ transport.cancel() → stateChanged(.disconnected)     │
└──────────────────────────────────────────────────────────┘
```

## Enlaces

- [01: Visión General de eD2k](01-ed2k-overview.md)
- [02: Paquetes eD2k TCP](02-ed2k-tcp-packets.md)
- [04: Sesiones Peer-to-Peer](04-peer-session.md)
- `ED2KServerSession.swift` — Implementación
- `ED2KServerTCPConnection.swift` — Conexión con transporte
