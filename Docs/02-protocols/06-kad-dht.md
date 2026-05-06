# Red Kademlia DHT (Kad)

## ¿Qué es Kad?

Kad es una red **Kademlia DHT** (Distributed Hash Table) que funciona sobre UDP. A diferencia de la red eD2k tradicional, Kad no depende de servidores centrales. Los nodos se organizan en una tabla hash distribuida donde cada nodo es responsable de almacenar metadatos sobre archivos cercanos a su ID.

## Arquitectura General

```
                           ┌─────────────┐
                           │  KadService │
                           └──────┬──────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
   ┌────▼────┐             ┌─────▼──────┐           ┌──────▼──────┐
   │Routing  │             │SearchManager│           │UDPListener  │
   │Table    │             │             │           │(puerto 4672)│
   └────┬────┘             └──────┬──────┘           └──────┬──────┘
        │                        │                         │
   ┌────▼────┐             ┌─────▼──────┐           ┌──────▼──────┐
   │Routing  │             │LookupCoord │           │PacketHandler│
   │Bins     │             │            │           │             │
   └─────────┘             └────────────┘           └─────────────┘
```

## Archivos Fuente (17+)

| Archivo | Propósito |
|---------|-----------|
| `KadService.swift` | Orquestación del módulo Kad (start/stop/mantenimiento) |
| `KadUInt128.swift` | Identificadores de 128 bits (nodeID, fileID, target) |
| `KadRoutingTable.swift` | Tabla Kademlia con buckets |
| `KadRoutingBin.swift` | Un bucket individual (hasta k=10 contactos) |
| `KadContact.swift` | Representación de un nodo remoto |
| `KadConstants.swift` | Constantes Kademlia (k, alpha, timeouts) |
| `KadSearchManager.swift` | Manejo de búsquedas activas |
| `KadLookupCoordinator.swift` | Búsqueda paralela de nodos cercanos a un target |
| `KadClientSearcher.swift` | Envío de paquetes FIND_NODE, PING, etc. |
| `KadUDPListener.swift` | Escucha/envío de paquetes UDP |
| `KadPacketHandler.swift` | Procesamiento de paquetes entrantes |
| `KadPacketTracker.swift` | Tracking de transacciones pendientes |
| `KadNodesStore.swift` | Persistencia de nodos en nodes.dat |
| `KadIndexed.swift` | Índice local de keywords, fuentes y notas |
| `KadPrefsStore.swift` | Preferencias del módulo Kad |

## Identificadores: KadUInt128

Todos los nodos y recursos se identifican con números de 128 bits:

```swift
public struct KadUInt128 {
    public var hi: UInt64   // 64 bits superiores
    public var lo: UInt64   // 64 bits inferiores

    public func commonPrefixBits(with other: KadUInt128) -> Int
    public func distance(to other: KadUInt128) -> KadUInt128  // XOR
    public func bitAt(_ position: Int) -> Bool
}
```

- La **distancia** entre dos IDs se calcula con XOR
- El **prefijo común** (common prefix bits) determina a qué bucket pertenece un contacto
- Se usa `KadUInt128.random()` para generar IDs aleatorios

## Tabla de Routing (Kademlia)

### Estructura

```
KadRoutingTable
├── selfNodeID: KadUInt128
├── buckets: [KadRoutingBin]
│   ├── [depth=0] contacts: [KadContact] (hasta k=10)
│   ├── [depth=1] contacts: [KadContact] (hasta k=10)
│   ├── [depth=2] contacts: [KadContact] (hasta k=10)
│   └── ...
```

### KadRoutingBin

```swift
public struct KadRoutingBin {
    public var contacts: [KadContact]
    public var lastChanged: Date
    public var depth: Int

    public var isFull: Bool { contacts.count >= KadConstants.kBucketSize }
}
```

- **k = 10** contactos máximo por bucket
- Los contactos se ordenan por `lastSeen` descendente
- Al insertar: si el bucket está lleno, se reemplaza el más antiguo si está expirado

### Inserción de Contactos

```swift
public func addContact(_ contact: KadContact) -> KadRoutingBinInsertResult {
    // .inserted → nuevo contacto agregado
    // .updated → contacto existente actualizado
    // .replacedExpired → reemplazó un contacto expirado
    // .rejectedBucketFull → bucket lleno sin expirados
}
```

### Splitting de Buckets

Cuando un bucket está lleno y su profundidad es menor que 127, se divide en dos:

```
Bucket [depth=d] lleno
    │
    ├── bit[d] = 0 → Bucket A [depth=d+1]
    └── bit[d] = 1 → Bucket B [depth=d+1]
```

### Búsqueda de Contactos Cercanos

```swift
public func closestContacts(to target: KadUInt128, maxCount: Int = 10) -> [KadContact]
```

Retorna hasta `k` contactos ordenados por distancia XOR al target. Esta es la operación fundamental de Kademlia.

## KadContact

```swift
public struct KadContact {
    public var nodeID: KadUInt128       // ID del nodo (128 bits)
    public var ipAddress: String        // dirección IPv4/IPv6
    public var udpPort: UInt16          // puerto UDP (default 4672)
    public var tcpPort: UInt16          // puerto TCP (default 4662)
    public var kadVersion: UInt8        // versión del protocolo Kad (def. 9)
    public var lastSeen: Date           // última vez visto
    public var verified: Bool           // PONG recibido

    public func distance(to other: KadUInt128) -> KadUInt128
    public var isExpired: Bool          // lastSeen > contactTimeout (3600s)
    public func touch() -> KadContact   // actualizar lastSeen
}
```

## Constantes Kademlia

```swift
public enum KadConstants {
    public static let kBucketSize = 10          // contactos máx. por bucket
    public static let alpha = 3                 // nodos paralelos en lookups
    public static let beta = 2                  // nodos para replicación
    public static let searchLifetime: TimeInterval = 60      // timeout de búsqueda
    public static let contactTimeout: TimeInterval = 3600    // expiración de contacto
    public static let bucketRefreshInterval: TimeInterval = 3600  // refresco de bucket
}
```

## KadService

Archivo: `KadService.swift`

Orquesta el ciclo de vida del módulo Kad:

```swift
public final class KadService {
    public var isRunning: Bool          // si el servicio está activo
    public var isConnected: Bool        // si hay al menos 1 contacto en la tabla
    public var isFirewalled: Bool       // si el nodo es LowID
    public let routingTable: KadRoutingTable
    public var selfNodeID: KadUInt128   // ID propio

    public func start()
    public func stop()
    public func bootstrap(from endpoints: [KadEndpoint]) async
    public func addContact(_ contact: KadContact)
    public func processMaintenance()
}
```

### Mantenimiento

El servicio ejecuta un timer cada `bucketRefreshInterval` (3600s) que:

1. Expira contactos stale (`routingTable.expireStale()`)
2. Elimina contactos con `lastSeen` mayor a `contactTimeout`

## KadSearchManager

Maneja búsquedas activas de keywords y fuentes:

```swift
public final class KadSearchManager {
    public func startSearch(id:type:target:searchTerms:) -> KadActiveSearch
    public func addResults(_ results: [KadSearchResultItem], to searchID: KadUInt128)
    public func completeSearch(_ searchID: KadUInt128)
    public func expireStaleSearches() -> [KadUInt128]
}
```

```swift
public struct KadActiveSearch {
    public var id: KadUInt128
    public var type: KadSearchType       // .keyword, .source, .findNode, etc.
    public var target: KadUInt128        // nodo target de la búsqueda
    public var searchTerms: Data?        // términos de búsqueda (keyword)
    public var results: [KadSearchResultItem]
    public var closestContacts: [KadContact]
}
```

Tipos de búsqueda:

```swift
public enum KadSearchType: UInt8 {
    case keyword = 0x02       // búsqueda por palabra clave
    case source = 0x03        // búsqueda de fuentes
    case notes = 0x06         // búsqueda de notas/comentarios
    case findNode = 0x0D      // lookup de nodo
    case findValue = 0x0E     // lookup de valor almacenado
    case store = 0x0F         // almacenar valor
}
```

## KadLookupCoordinator

Coordina la búsqueda Kademlia paralela (α = 3 nodos simultáneos):

```
findNodes(target)
    │
    ├── 1. closestContacts(target, α=3) → enviar FIND_NODE a cada uno
    │
    ├── 2. Esperar respuestas (3s)
    │
    ├── 3. Agregar nuevos contactos recibidos
    │
    ├── 4. closestContacts(target, α=3) de los no consultados
    │      └── enviar FIND_NODE
    │
    ├── 5. Esperar respuestas (3s)
    │
    └── 6. Retornar k contactos más cercanos ordenados
```

## Paquetes Kad (UDP)

### Formato de Paquete

```
┌─────────┬─────────┬──────────────────┬──────────────────┐
│ Proto   │ Opcode  │  Transaction ID  │     Payload      │
│ (0xE4)  │ (1 byte)│   (16 bytes)     │   (variable)     │
└─────────┴─────────┴──────────────────┴──────────────────┘
```

- **Protocol byte**: `0xE4` (Kad)
- **Opcode**: tipo de paquete (ver `KadPacketOpcode`)
- **Transaction ID**: `KadUInt128` (16 bytes) para correlacionar respuestas
- **Payload**: datos variables según opcode

### Opcodes

```swift
public enum KadPacketOpcode: UInt8 {
    case bootstrapReq = 0x00    // solicitud de bootstrap
    case bootstrapRes = 0x08    // respuesta de bootstrap
    case helloReq = 0x10        // PING
    case helloRes = 0x18        // PONG
    case req = 0x20             // FIND_NODE / FIND_VALUE
    case res = 0x28             // respuesta con contactos
    case searchReq = 0x30       // búsqueda (keyword/source/notes)
    case searchRes = 0x38       // resultados de búsqueda
    case publishReq = 0x40      // publicar keyword/source
    case publishRes = 0x48      // confirmación de publicación
    case firewallReq = 0x50     // solicitud de firewall check
    case firewallRes = 0x58     // respuesta firewall
    case firewallAck = 0x59     // acknowledge firewall
}
```

Los opcodes pares (bit 0 = 0) son **requests**; los impares (bit 0 = 1) son **responses**:

```swift
public var isRequest: Bool { rawValue & 0x01 == 0 }
public var responseOpcode: KadPacketOpcode? { KadPacketOpcode(rawValue: rawValue | 0x08) }
```

## KadUDPListener

Escucha y envía paquetes UDP usando `NWListener`:

```swift
public final class KadUDPListener {
    public func start(port: UInt16) throws
    public func stop()
    public func sendPacket(_ data: Data, to endpoint: KadEndpoint)
    public func setPacketHandler(_ handler: KadUDPPacketHandler)
}
```

- Usa `NWParameters.udp` con `allowLocalEndpointReuse = true`
- Cada paquete enviado crea una conexión UDP temporal (`NWConnection`)

## KadPacketHandler

Procesa paquetes entrantes:

1. Verifica protocol byte `0xE4`
2. Extrae opcode y transaction ID
3. Si es una **respuesta** a una solicitud pendiente → `handleResponse()`
4. Si es una **solicitud** entrante → `handleRequest()`

### Manejo de Respuestas

| Respuesta | Acción |
|-----------|--------|
| `helloRes` (PONG) | Extrae NodeID, agrega contacto verificado a routing table |
| `res` (FIND_NODE) | Parsea contactos (16 bytes c/u), notifica lookup coordinator |
| `searchRes` | Parsea resultados, notifica lookup coordinator |

### Manejo de Solicitudes

| Solicitud | Respuesta |
|-----------|-----------|
| `helloReq` (PING) | Envía `helloRes` |
| `req` + findNode | Busca closest contacts, envía `res` |
| `searchReq` + source | Busca fuentes en `KadIndexed`, envía `searchRes` |
| `searchReq` + keyword | Busca keywords en `KadIndexed`, envía `searchRes` |
| `publishReq` | Almacena en `KadIndexed`, envía `publishRes` |

## KadPacketTracker

Asocia transacciones pendientes con respuestas esperadas:

```swift
public final class KadPacketTracker {
    public func nextID() -> KadUInt128                     // ID incremental
    public func track(send:transaction:expectedResponse:)  // registrar solicitud
    public func matchResponse(opcode:transaction:)         // correlacionar respuesta
    public func expireAndCollect() -> [PendingRequest]     // limpiar timeouts (10s)
}
```

## KadClientSearcher

Cliente para enviar solicitudes Kad a nodos específicos:

| Método | Paquete | Propósito |
|--------|---------|-----------|
| `sendPing(to:)` | `helloReq` (0x10) | Verificar si un nodo está vivo |
| `sendFindNode(target:to:)` | `req` (0x20) + findNode | Buscar nodos cercanos |
| `sendFindValue(target:to:)` | `req` (0x20) + findValue | Buscar valor almacenado |
| `sendStore(target:value:to:)` | `req` (0x20) + store | Almacenar valor |

## KadNodesStore

Persistencia de nodos conocidos en `nodes.dat`:

```
# MacMule Kad nodes.dat
# Format: nodeID,ip,udpPort,tcpPort,version,lastSeen
a1b2c3d4...,192.168.1.1,4672,4662,9,1700000000
```

- Formato CSV: `nodeIDhex,ip,udpPort,tcpPort,kadVersion,timestamp`
- Límite: 5000 nodos
- Merge: combina listas existentes con nuevas, mantiene más recientes

## KadIndexed

Índice local de datos publicados por otros nodos:

- **Keywords**: archivos indexados por palabra clave
- **Sources**: fuentes por fileHash
- **Notes**: comentarios por fileHash

Con tiempos de vida (TTL):
- Keywords: 24h (`keywordTTL = 86400s`)
- Sources: 6h (`sourceTTL = 21600s`)
- Notes: 36h (`notesTTL = 129600s`)

## Bootstrap

El módulo Kad necesita al menos un contacto inicial para unirse a la red:

```
┌──────────────────────────────────────────────┐
│ Bootstrap desde nodes.dat o eD2k peers       │
│                                              │
│ 1. Cargar nodos de nodes.dat                 │
│ 2. Enviar PING a α=3 nodos                   │
│ 3. Esperar PONGs (3s)                        │
│ 4. Si hay contactos → isConnected = true     │
│ 5. Sino → intentar con peers conocidos eD2k  │
└──────────────────────────────────────────────┘
```

## Firewalled Kad

Cuando un nodo está firewalled (no recibe conexiones entrantes):

- `isFirewalled = true`
- `firewallState = .firewalled`
- No puede recibir respuestas UDP de nodos arbitrarios
- Usa **callbacks** para comunicación indirecta

Estados de firewall:

```swift
public enum KadFirewallState {
    case unknown       // estado inicial
    case open          // nodo accesible (HighID)
    case firewalled    // nodo detrás de NAT/firewall (LowID)
}
```

## Enlaces

- [01: Visión General de eD2k](01-ed2k-overview.md)
- [02: Paquetes eD2k TCP](02-ed2k-tcp-packets.md)
- `KadService.swift` — Servicio principal
- `KadRoutingTable.swift` — Tabla de routing Kademlia
- `KadSearchManager.swift` — Gestión de búsquedas
