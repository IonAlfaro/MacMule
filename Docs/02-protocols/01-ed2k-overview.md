# Visión General de la Red eD2k

## ¿Qué es eD2k?

eD2k (eDonkey2000) es una red peer-to-peer híbrida para el intercambio de archivos. Combina **servidores centralizados** que mantienen índices de archivos con **transferencias directas** entre pares (peers).

## Arquitectura de la Red

```
                    ┌──────────────────┐
                    │   Servidor eD2k  │
                    │  (índice/búsq.)  │
                    └────────┬─────────┘
                             │
             ┌───────────────┼───────────────┐
             │               │               │
        ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
        │ Cliente │◄──►│ Cliente │◄──►│ Cliente │
        │ (peer)  │    │ (peer)  │    │ (peer)  │
        └─────────┘    └─────────┘    └─────────┘
```

- **Servidores** — mantienen catálogos de archivos compartidos por clientes conectados
- **Peers** — intercambian partes de archivos directamente (TCP peer-to-peer)
- **Kad** — red DHT distribuida que no requiere servidores

## Los 3 Protocolos Principales

### 1. eD2k TCP (Servidor) — Puertos 4661–4672

Conexión TCP cliente → servidor para:

| Operación | Descripción |
|-----------|-------------|
| **Login** | Autenticación; el servidor asigna un `clientID` |
| **Búsqueda** | Envío de consultas por palabra clave |
| **Fuentes** | Solicitud de peers que poseen un archivo |
| **Server List** | Obtención de otros servidores conocidos |
| **Callbacks** | El servidor conecta dos peers para transferencias |

**Archivos**: `ED2KServerTCPConnection.swift`, `ED2KServerSession.swift`

**Flujo típico**:

```
Cliente                     Servidor
   │                           │
   ├── loginRequest ──────────►│
   │                           ├── serverIdent
   │                           ├── idChange (clientID)
   │◄──────────────────────────┤
   ├── search ────────────────►│
   │◄── searchResults ────────┤
   ├── getSources ────────────►│
   │◄── foundSources ─────────┤
   ├── callbackRequest ───────►│
   │◄── callbackRequested ─────┤
   │◄── serverMessage ────────┤
```

### 2. eD2k TCP (Peer) — Puerto configurable (default 4662)

Conexión TCP peer-to-peer para transferencia de datos:

| Operación | Descripción |
|-----------|-------------|
| **Handshake** | Hello/HelloAnswer, negociación de capacidades |
| **Partes** | Solicitud y envío de bloques de archivos |
| **Source Exchange** | Intercambio de fuentes entre peers (ext. eMule) |
| **HashSet** | Solicitud del conjunto de hashes de partes |

**Archivos**: `ED2KPeerSession.swift`, `ED2KPeerTCPConnection.swift`

**Flujo típico**:

```
Peer A (descarga)             Peer B (subida)
   │                              │
   ├── hello ───────────────────►│
   │◄── helloAnswer ─────────────┤
   ├── setRequestFileID ────────►│
   ├── requestParts ────────────►│
   │◄── sendingPart ─────────────┤
   ├── requestSources2 ─────────►│
   │◄── answerSources2 ──────────┤
```

### 3. Kad UDP — Puerto configurable (default 4672)

Red Kademlia DHT distribuida:

| Componente | Descripción |
|-----------|-------------|
| **Routing Table** | Buckets Kademlia con k=10 contactos cada uno |
| **Búsqueda keywords** | Distribuida sin servidor central |
| **Búsqueda fuentes** | Find node / find value |
| **Publicación** | Store de metadatos en nodos cercanos al target |

**Archivos**: 17+ archivos, núcleo en `KadService.swift`, `KadRoutingTable.swift`, `KadSearchManager.swift`

## Tecnología de Red: Network.framework

MacMule usa **Apple Network.framework** (`NWConnection`/`NWListener`) en lugar de sockets BSD. Esto proporciona:

- Soporte nativo IPv4/IPv6
- Multipath TCP
- TLS/DTLS integrado
- Calidad de servicio (QoS)
- Manejo eficiente de conexiones

## Archivos Fuente Clave

| Componente | Archivo |
|-----------|---------|
| Definiciones de paquetes y opcodes | `Sources/MacMuleCore/ED2KProtocol.swift` |
| Sesión con servidor | `Sources/MacMuleCore/ED2KServerSession.swift` |
| Conexión TCP al servidor | `Sources/MacMuleCore/ED2KServerTCPConnection.swift` |
| Sesión peer-to-peer | `Sources/MacMuleCore/ED2KPeerSession.swift` |
| Conexión TCP al peer | `Sources/MacMuleCore/ED2KPeerTCPConnection.swift` |
| Listener TCP entrante | `Sources/MacMuleCore/ED2KPeerTCPListener.swift` |
| Listener UDP (eD2k) | `Sources/MacMuleCore/ED2KUDPListener.swift` |
| Servicio Kad | `Sources/MacMuleCore/KadService.swift` |
| Tabla de routing Kademlia | `Sources/MacMuleCore/KadRoutingTable.swift` |
| Búsquedas Kad | `Sources/MacMuleCore/KadSearchManager.swift` |

## Documentos Relacionados

- [02: Paquetes eD2k TCP](02-ed2k-tcp-packets.md)
- [03: Sesiones con Servidor](03-server-session.md)
- [04: Sesiones Peer-to-Peer](04-peer-session.md)
- [05: Listener TCP de Peers](05-peer-listener.md)
- [06: Red Kademlia DHT (Kad)](06-kad-dht.md)
