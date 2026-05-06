# Paquete MacMuleCore

## Propósito

`MacMuleCore` es el paquete Swift que contiene todo el motor de protocolo eD2k, la red Kad DHT, los servicios de transferencia, seguridad y utilidades. Es un paquete SwiftPM independiente y reutilizable, sin dependencias de AppKit o SwiftUI.

## Package.swift

`MacMuleCore/Package.swift:1`

```
swift-tools-version: 6.0
platforms: macOS .v15
```

### Productos

| Producto | Tipo | Descripción |
|---|---|---|
| MacMuleCore | library | Framework con el motor completo |
| macmule-core-daemon | executable | Daemon CLI (véase [03-daemon-layer.md](03-daemon-layer.md)) |

### Targets

| Target | Dependencias | Descripción |
|---|---|---|
| MacMuleZlib | libz (sistema) | C bridge para compresión zlib de paquetes eD2k |
| MacMuleCore | MacMuleZlib | Motor principal del protocolo |
| MacMuleCoreDaemon | MacMuleCore | Ejecutable daemon (1 archivo: main.swift) |
| MacMuleCoreTests | MacMuleCore | Tests unitarios |

```
MacMuleCore/
├── Package.swift
├── Sources/
│   ├── MacMuleZlib/
│   │   └── (C wrapper para libz)
│   ├── MacMuleCore/          ← 43 archivos fuente
│   │   ├── ED2KProtocol.swift
│   │   ├── KadService.swift
│   │   ├── CoreService.swift
│   │   ├── CoreIPFilter.swift
│   │   ├── CoreRPC.swift
│   │   └── ...
│   └── MacMuleCoreDaemon/
│       └── main.swift
└── Tests/
    └── MacMuleCoreTests/
```

## Categorías de Archivos Fuente

### Protocolo eD2k (6 archivos)

| Archivo | Ruta | Responsabilidad |
|---|---|---|
| ED2KProtocol.swift | MacMuleCore/Sources/MacMuleCore/ED2KProtocol.swift | Definiciones del protocolo eD2k: códigos de operación, estructuras de paquetes, serialización/deserialización |
| ED2KServerSession.swift | MacMuleCore/Sources/MacMuleCore/ED2KServerSession.swift | Maneja una sesión con un servidor eD2k: login, callbacks de estado, heartbeat |
| ED2KServerTCPConnection.swift | MacMuleCore/Sources/MacMuleCore/ED2KServerTCPConnection.swift | Conexión TCP a un servidor eD2k usando Network.framework |
| ED2KPeerSession.swift | MacMuleCore/Sources/MacMuleCore/ED2KPeerSession.swift | Sesión con un peer: negociación, compresión, upload/download de partes |
| ED2KPeerTCPConnection.swift | MacMuleCore/Sources/MacMuleCore/ED2KPeerTCPConnection.swift | Conexión TCP saliente a un peer |
| ED2KPeerTCPListener.swift | MacMuleCore/Sources/MacMuleCore/ED2KPeerTCPListener.swift | Listener TCP para conexiones entrantes de peers |

### Kad DHT (15 archivos)

| Archivo | Ruta | Responsabilidad |
|---|---|---|
| KadService.swift | MacMuleCore/Sources/MacMuleCore/KadService.swift | Orquestador principal de Kad: bootstrap, búsquedas, ciclo de vida |
| KadRoutingTable.swift | MacMuleCore/Sources/MacMuleCore/KadRoutingTable.swift | Tabla de enrutamiento Kademlia (implementación del bucket trie) |
| KadRoutingBin.swift | MacMuleCore/Sources/MacMuleCore/KadRoutingBin.swift | Un bucket de la tabla de enrutamiento (k-bucket) |
| KadSearchManager.swift | MacMuleCore/Sources/MacMuleCore/KadSearchManager.swift | Gestiona búsquedas activas en Kad (palabras clave, fuentes, hashes) |
| KadUDPListener.swift | MacMuleCore/Sources/MacMuleCore/KadUDPListener.swift | Listener UDP para mensajes Kad |
| KadContact.swift | MacMuleCore/Sources/MacMuleCore/KadContact.swift | Representación de un nodo Kad (ID, dirección, UDP port) |
| KadUInt128.swift | MacMuleCore/Sources/MacMuleCore/KadUInt128.swift | Tipo UInt128 para IDs Kad |
| KadNodesStore.swift | MacMuleCore/Sources/MacMuleCore/KadNodesStore.swift | Almacenamiento persistente de nodos Kad conocidos |
| KadPacketHandler.swift | MacMuleCore/Sources/MacMuleCore/KadPacketHandler.swift | Procesa y despacha paquetes Kad entrantes |
| KadPacketTracker.swift | MacMuleCore/Sources/MacMuleCore/KadPacketTracker.swift | Rastrea paquetes enviados para detección de timeouts/retransmisiones |
| KadClientSearcher.swift | MacMuleCore/Sources/MacMuleCore/KadClientSearcher.swift | Algoritmo de búsqueda de clientes en Kad |
| KadLookupCoordinator.swift | MacMuleCore/Sources/MacMuleCore/KadLookupCoordinator.swift | Coordina búsquedas iterativas Kademlia (SERIAL/ALPHA lookup) |
| KadPrefsStore.swift | MacMuleCore/Sources/MacMuleCore/KadPrefsStore.swift | Preferencias persistentes de Kad (nodos, metadata) |
| KadIndexed.swift | MacMuleCore/Sources/MacMuleCore/KadIndexed.swift | Índice local de palabras clave y fuentes publicadas |
| KadConstants.swift | MacMuleCore/Sources/MacMuleCore/KadConstants.swift | Constantes de Kad (K, ALPHA, tiempos, IDs de tags) |

### Core Services (7 archivos)

| Archivo | Ruta | Responsabilidad |
|---|---|---|
| CoreService.swift | MacMuleCore/Sources/MacMuleCore/CoreService.swift | Servicio central que orquesta todas las operaciones del motor |
| CoreTransferStore.swift | MacMuleCore/Sources/MacMuleCore/CoreTransferStore.swift | Almacenamiento y gestión de transfers activos (descargas/subidas) |
| CoreUploadQueue.swift | MacMuleCore/Sources/MacMuleCore/CoreUploadQueue.swift | Cola de subidas con scheduling por prioridad y créditos |
| CoreSharedFileList.swift | MacMuleCore/Sources/MacMuleCore/CoreSharedFileList.swift | Lista de archivos compartidos, hashing y publicación |
| CoreKnownFileList.swift | MacMuleCore/Sources/MacMuleCore/CoreKnownFileList.swift | Lista de archivos conocidos (metadatos de archivos vistos) |
| CoreScheduler.swift | MacMuleCore/Sources/MacMuleCore/CoreScheduler.swift | Planificador de horarios (limitar ancho de banda por franja horaria) |
| CoreWebServer.swift | MacMuleCore/Sources/MacMuleCore/CoreWebServer.swift | Servidor HTTP embebido para Web UI/API |

### Seguridad (4 archivos)

| Archivo | Ruta | Responsabilidad |
|---|---|---|
| CoreIPFilter.swift | MacMuleCore/Sources/MacMuleCore/CoreIPFilter.swift | Filtro de IPs (bloqueo de IPs conocidas como maliciosas) |
| CoreSecureIdent.swift | MacMuleCore/Sources/MacMuleCore/CoreSecureIdent.swift | Identificación segura (firma criptográfica de identificador de usuario) |
| CoreObfuscationLayer.swift | MacMuleCore/Sources/MacMuleCore/CoreObfuscationLayer.swift | Capa de ofuscación de protocolo (anti-throttling) |
| CoreCreditsList.swift | MacMuleCore/Sources/MacMuleCore/CoreCreditsList.swift | Sistema de créditos (recompensa a usuarios que suben) |

### Utilidades (11 archivos)

| Archivo | Ruta | Responsabilidad |
|---|---|---|
| CoreCorruptionBlackBox.swift | MacMuleCore/Sources/MacMuleCore/CoreCorruptionBlackBox.swift | Detección de corrupción en partes descargadas |
| CoreRarityScheduler.swift | MacMuleCore/Sources/MacMuleCore/CoreRarityScheduler.swift | Prioriza descarga de partes raras (algoritmo de rareza) |
| CoreRPC.swift | MacMuleCore/Sources/MacMuleCore/CoreRPC.swift | Parser/serializador JSON-RPC 2.0 |
| CoreSocketServer.swift | MacMuleCore/Sources/MacMuleCore/CoreSocketServer.swift | Servidor de Unix socket para IPC |
| CoreModels.swift | MacMuleCore/Sources/MacMuleCore/CoreModels.swift | Modelos de datos compartidos (TransferItem, SearchResult, ServerSnapshot, etc.) |
| DefaultED2KServers.swift | MacMuleCore/Sources/MacMuleCore/DefaultED2KServers.swift | Lista de servidores eD2k por defecto para bootstrap |
| ED2KHash.swift | MacMuleCore/Sources/MacMuleCore/ED2KHash.swift | Cálculo de hash MD4 de archivos (formato eD2k) |
| ED2KLink.swift | MacMuleCore/Sources/MacMuleCore/ED2KLink.swift | Parser de links ed2k:// |
| UPnPPortMapper.swift | MacMuleCore/Sources/MacMuleCore/UPnPPortMapper.swift | UPnP IGD para abrir puertos automáticamente |
| NATPMPPortMapper.swift | MacMuleCore/Sources/MacMuleCore/NATPMPPortMapper.swift | NAT-PMP para abrir puertos automáticamente |
| ED2KUDPListener.swift | MacMuleCore/Sources/MacMuleCore/ED2KUDPListener.swift | Listener UDP para mensajes eD2k |

## Tests

Los tests unitarios están en **MacMuleCore/Tests/MacMuleCoreTests/**, con dependencia en MacMuleCore.

## MacMuleZlib

**MacMuleCore/Sources/MacMuleZlib/** es un target C/Objective-C que enlaza con libz del sistema. Proporciona funciones de compresión/descompresión usadas por el protocolo eD2k para paquetes grandes.

## Dependencias

```
MacMuleCoreDaemon
    └── MacMuleCore
            └── MacMuleZlib
                    └── libz (sistema)
```

## Enlaces

- [Visión General](01-overview.md)
- [Capa de Aplicación](02-app-layer.md)
- [Capa de Daemon](03-daemon-layer.md)
