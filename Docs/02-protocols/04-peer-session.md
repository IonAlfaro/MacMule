# Sesiones Peer-to-Peer eD2k

## Arquitectura

La comunicación peer-to-peer se organiza en dos capas:

```
┌──────────────────────────────────────────────┐
│           ED2KPeerTCPConnection                │
│  - Ciclo de vida connect/disconnect           │
│  - Envío de comandos (requestParts, etc.)      │
│  - Reenvío de eventos                         │
├──────────────────────┬───────────────────────┤
│  ED2KPeerSession     │  ED2KPeerTCPTransport  │
│  - Hello/HelloAnswer │  - NWConnection        │
│  - Decode de paquetes│  - Send/Receive        │
│  - Eventos           │  - Intercambiable      │
└──────────────────────┴───────────────────────┘
```

## ED2KPeerTCPConnection

Archivo: `ED2KPeerTCPConnection.swift`

### Estados

```swift
public enum ED2KPeerTCPConnectionState {
    case connecting          // Iniciando conexión TCP saliente
    case connected           // Conexión establecida, hello enviado
    case disconnected        // Desconectado
    case failed(String)      // Error
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
    │ connecting│
    └─────┬─────┘
          │ NWConnection .ready
          ▼
     ┌─────────┐
     │ connected│ ← sendHello()
     │          │ ← receiveNext()
     └────┬─────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
┌──────────┐ ┌──────┐
│disconnected│ │failed│
└──────────┘ └──────┘
```

### Transporte

`ED2KPeerTCPTransport` es el protocolo que abstrae el transporte TCP:

```swift
public protocol ED2KPeerTCPTransport: AnyObject {
    var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)? { get set }
    var receiveHandler: ((Data) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func send(_ data: Data, completion: @escaping (ED2KPeerTCPTransportSendResult) -> Void)
    func receiveNext()
    func cancel()
}
```

Implementación real: `NetworkED2KPeerTCPTransport` — usa `NWConnection`

## ED2KPeerSession

Archivo: `ED2KPeerSession.swift`

### Configuración

```swift
public struct ED2KPeerSessionConfiguration {
    public var userHash: Data              // hash del usuario (16 bytes)
    public var clientID: UInt32            // ID propio
    public var tcpPort: UInt16             // puerto TCP local (def. 4662)
    public var nickname: String            // "MacMule"
    public var version: String             // "MacMule/0.1"
    public var serverEndpoint: ED2KServerEndpoint  // servidor al que estamos conectados
}
```

### Handshake Hello/HelloAnswer

```
Cliente (conexión entrante)          Peer remoto
  │                                      │
  │──── hello (0x01) ──────────────────► │
  │    hashLength (0x10 = 16)            │
  │    userHash (16 bytes)               │
  │    clientID (UInt32 LE)              │
  │    tcpPort (UInt16 LE)               │
  │    tagCount (UInt32 LE)              │
  │    tags:                             │
  │      nick (0x01)                     │
  │      version (0x11)                  │
  │      flags (0xF9)                    │
  │      flags2 (0xFA)                   │
  │      flags3 (0xFE)                   │
  │      muleVersion (0xFB)              │
  │    serverIP (4 bytes octets)         │
  │    serverPort (UInt16 LE)            │
  │                                      │
  │◄─── helloAnswer (0x4C) ──────────── │
  │    (sin hashLength)                  │
  │    userHash (16 bytes)               │
  │    clientID (UInt32 LE)              │
  │    ... (mismos campos que hello)     │
```

- `hello` incluye `hashLength` byte (`0x10`)
- `helloAnswer` **no** incluye `hashLength` (diferencia clave en decode)

### Eventos de Sesión

```swift
public enum ED2KPeerSessionEvent {
    case outgoingHello(ED2KPacket)
    case outgoingHelloAnswer(ED2KPacket)
    case outgoingFileRequest(ED2KPacket)
    case outgoingSetRequestFileID(ED2KPacket)
    case outgoingStartUploadRequest(ED2KPacket)
    case outgoingSourceExchangeRequest(ED2KPacket)
    case peerHello(ED2KPeerHello)                    // hello entrante
    case peerHelloAnswer(ED2KPeerHello)               // helloAnswer entrante
    case partHashSet(ED2KPartHashSet)                 // hashSetAnswer (0x52)
    case sourceExchangeAnswer(ED2KPeerSourceExchangeAnswer)
    case partRequest(ED2KPartRequest)                 // requestParts (0x47/0xA3)
    case sendingPart(ED2KSendingPart)                 // sendingPart (0x46/0xA2/0x40/0xA1)
    case fileRequestAnswerNoFile(Data)                // archivo no disponible
    case acceptUploadRequest                          // acceptUpload (0x55)
    case queueRank(UInt32)                            // posición en cola
    case unhandledPacket(ED2KPacket)
}
```

### Métodos de Sesión

| Método | Opcode | Propósito |
|--------|--------|-----------|
| `helloPacket()` | `0x01` | Paquete de saludo |
| `helloAnswerPacket()` | `0x4C` | Respuesta al hello |
| `partRequestPacket(fileHash:ranges:)` | `0x47`/`0xA3` | Solicitar partes |
| `partHashSetRequestPacket(fileHash:)` | `0x51` | Solicitar hashset |
| `fileRequestPacket(fileHash:)` | `0x58` | Solicitar nombre de archivo |
| `setRequestFileIDPacket(fileHash:)` | `0x4F` | Seleccionar archivo a descargar |
| `startUploadRequestPacket(fileHash:)` | `0x54` | Solicitar inicio de subida |
| `sourceExchangeRequestPacket(fileHash:)` | `0x83` | Solicitar intercambio de fuentes |
| `receive(_ data:)` | — | Procesar datos → `[ED2KPeerSessionEvent]` |

## Solicitud de Partes

```swift
public struct ED2KPartRequest {
    public var fileHash: Data                // 16 bytes
    public var ranges: [ED2KPartRange]       // 1-3 rangos
}

public struct ED2KPartRange {
    public var startOffset: UInt64
    public var endOffset: UInt64
}
```

- Soporta hasta 3 rangos por solicitud
- Usa opcode `0x47` (32-bit offsets) o `0xA3` (64-bit) según el tamaño del archivo
- Los rangos con start=0 y end=0 se consideran vacíos

## Envío de Partes

```swift
public struct ED2KSendingPart {
    public var fileHash: Data       // hash del archivo
    public var startOffset: UInt64  // offset inicial
    public var endOffset: UInt64    // offset final
    public var block: Data          // datos de la parte
}
```

- **`0x46`/`0x40`**: sendingPart/compressedPart con offsets 32-bit
- **`0xA2`/`0xA1`**: sendingPartI64/compressedPartI64 con offsets 64-bit
- Las partes comprimidas usan zlib (`ED2KPackedPacketDecoder.inflateZlib`)

## Solicitud de Hashset

```
Cliente                          Peer
  │                                │
  │── hashSetRequest (0x51) ─────►│
  │    fileHash (16 bytes)         │
  │                                │
  │◄── hashSetAnswer (0x52) ──────│
  │    fileHash (16 bytes)         │
  │    partCount (UInt16 LE)       │
  │    partHashes (16 bytes cada)  │
```

```swift
public struct ED2KPartHashSet {
    public var fileHash: Data      // hash del archivo
    public var partHashes: [Data]  // hashes MD4 de cada parte (16 bytes cada uno)
}
```

## Source Exchange

```
Cliente                          Peer
  │                                │
  │── requestSources2 (0x83) ────►│
  │    version (UInt8 = 4)         │
  │    pad (UInt16 = 0)            │
  │    fileHash (16 bytes)         │
  │                                │
  │◄── answerSources2 (0x84) ─────│
  │    version (UInt8)             │
  │    fileHash (16 bytes)         │
  │    sourceCount (UInt16 LE)     │
  │    sources[]:                  │
  │      clientID (UInt32 LE)      │
  │      clientPort (UInt16 LE)    │
  │      serverIP (UInt32 LE)      │
  │      serverPort (UInt16 LE)    │
  │      userHash (16 bytes, v2+) │
  │      cryptOptions (1 byte, v4)│
```

Versiones de source exchange: 1 (original), 2 (+userHash), 3, 4 (+cryptOptions).

## Queue Ranking

Cuando un peer está ocupado, responde con `queueRank` (`0x5C`):

```
┌──────────┐
│queueRank │ = 0 → aceptado, puede descargar
│(UInt32)  │ > 0 → posición en cola de espera
└──────────┘
```

## Flujo Completo de Descarga

```
┌─────────────────────────────────────────────────────────┐
│ 1. ED2KPeerTCPConnection(endpoint:config:).start()      │
│    ├─ stateChanged(.connecting)                          │
│    └─ transport.start(queue:) → NWConnection            │
│                                                          │
│ 2. NWConnection.state → .ready                          │
│    ├─ stateChanged(.connected)                           │
│    ├─ sendHello() → hello packet                        │
│    └─ receiveNext()                                     │
│                                                          │
│ 3. Peer responde → helloAnswer                          │
│    ├─ .peerHelloAnswer → validar peer                   │
│    └─ verificar userHash, clientID, etc.                │
│                                                          │
│ 4. Enviar comandos de descarga                           │
│    ├─ sendSetRequestFileID(hash) → seleccionar archivo   │
│    ├─ sendPartRequest(hash, ranges) → solicitar partes   │
│    │  (o sendPartHashSetRequest para obtener hashset)    │
│    └─ sendSourceExchangeRequest(hash) → más fuentes      │
│                                                          │
│ 5. Recibir datos                                         │
│    ├─ .sendingPart → datos de parte recibidos            │
│    ├─ .partHashSet → hashset de partes                   │
│    ├─ .sourceExchangeAnswer → nuevas fuentes             │
│    └─ .queueRank → esperar turno                         │
│                                                          │
│ 6. ED2KPeerTCPConnection.cancel()                        │
│    └─ transport.cancel() → .disconnected                 │
└─────────────────────────────────────────────────────────┘
```

## Enlaces

- [01: Visión General de eD2k](01-ed2k-overview.md)
- [02: Paquetes eD2k TCP](02-ed2k-tcp-packets.md)
- [05: Listener TCP de Peers](05-peer-listener.md)
- `ED2KPeerSession.swift` — Implementación de la sesión peer
- `ED2KPeerTCPConnection.swift` — Implementación de la conexión TCP
