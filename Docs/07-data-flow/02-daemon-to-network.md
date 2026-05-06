# Flujo Daemon → Red eD2k

## Comunicación Daemon ↔ Red

El daemon maneja toda la comunicación de red:

```
┌───────────────────────┐
│  macmule-core-daemon  │
│                       │
│  ┌─────────────────┐  │
│  │ eD2k TCP Server │──│─────► Servidores eD2k (TCP:4661-4672)
│  │ (ServerSession) │  │      - Login, Search, GetSources
│  └─────────────────┘  │
│                       │
│  ┌─────────────────┐  │
│  │ eD2k Peer TCP   │──│─────► Peers red eD2k (TCP configurable)
│  │ (PeerSession)   │  │      - Handshake, Part transfer
│  └─────────────────┘  │
│                       │
│  ┌─────────────────┐  │
│  │ Kad UDP Listener│──│─────► Red Kad (UDP:4672)
│  │ (KadService)    │  │      - Kademlia DHT
│  └─────────────────┘  │
│                       │
│  ┌─────────────────┐  │
│  │ CoreTransferStore│  │      Gestión de transferencias
│  └─────────────────┘  │
└───────────────────────┘
```

## Network.framework

Usa Apple **Network.framework** (`NWConnection`, `NWListener`) en lugar de BSD sockets:

- `NWConnection`: conexiones TCP salientes (servidores, peers)
- `NWListener`: listener TCP entrante (peers conectándose a nosotros)
- `NWParameters.udp`: listener UDP para Kad

## Conexiones eD2k TCP

### Servidor (ED2KServerTCPConnection)

```
NWConnection(host: "server.ed2k.com", port: 4661, using: .tcp)
  ↓
connection.start(queue:)
  ↓
stateUpdateHandler(.ready)
  ↓
send(data: loginRequest)
  ↓
receiveMessage → handle response
```

### Peer (ED2KPeerTCPConnection)

```
NWConnection(host: "1.2.3.4", port: 4662, using: .tcp)
  ↓
Handshake: hello → helloAnswer
  ↓
requestParts → sendingPart → writeBlock
```

### Listener (ED2KPeerTCPListener)

```
NWListener(using: .tcp, on: 4662)
  ↓
newConnectionHandler → ED2KPeerSession
```

## Kad UDP (KadUDPListener)

```
NWListener(using: .udp, on: 4672)
  ↓
receiveMessage → handleKadPacket
```

Envío: `NWConnection(host:port:, using: .udp)` por paquete.

## Stack de Red

| Capa | Protocolo | Framework |
|------|-----------|-----------|
| Transporte | TCP/UDP | Network.framework |
| Sesión eD2k | eD2k Protocol | Swift structs + Codable |
| Aplicación | JSON-RPC | Unix socket |

## Referencias

- [App to Daemon](01-app-to-daemon.md) — capa superior
- [Peer Download Flow](03-peer-download-flow.md) — flujo completo
- [ED2K Protocol Overview](../02-protocols/01-ed2k-overview.md)
