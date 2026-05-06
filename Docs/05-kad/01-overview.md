# Kad en MacMule — Red Kademlia DHT

## ¿Qué es Kad?

Kad (Kademlia DHT) es una red **distribuida** peer-to-peer que no depende de servidores centrales. En MacMule, Kad permite:

- **Búsqueda de archivos** sin conectarse a un servidor eD2k
- **Búsqueda de fuentes** (peers que tienen un archivo)
- **Publicación** de recursos compartidos
- **Red descentralizada**: cada nodo es un peer en la DHT

## Componentes (17+ archivos)

| Archivo | Propósito |
|---------|-----------|
| `KadService.swift` | Orquestador principal del servicio Kad |
| `KadRoutingTable.swift` | Tabla de routing Kademlia con buckets |
| `KadRoutingBin.swift` | Bucket individual de la tabla |
| `KadSearchManager.swift` | Búsquedas activas de keywords y fuentes |
| `KadLookupCoordinator.swift` | Búsqueda paralela de nodos cercanos |
| `KadUDPListener.swift` | Escucha/sender UDP en puerto configurable |
| `KadPacketHandler.swift` | Manejo de paquetes Kad entrantes |
| `KadContact.swift` | Representación de un nodo en la red |
| `KadPrefsStore.swift` | Preferencias de Kad |
| `KadUInt128.swift` | Entero de 128 bits para IDs Kademlia |
| `KadEndpoint.swift` | Dirección IP+puerto de un nodo Kad |
| `KadClientSearcher.swift` | Envío de peticiones find_node/find_value |
| ... | (tipos auxiliares + extensiones) |

## Puerto

Puerto UDP por defecto: **4672**. Configurable vía `MacMuleStore.udpPort`.

## Arquitectura

```
┌─────────────────────────────────────────────────────┐
│                    KadService                       │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │RoutingTable │  │SearchManager │  │LookupCoord │ │
│  └──────┬──────┘  └──────┬───────┘  └─────┬──────┘ │
│         │                │                 │        │
│  ┌──────┴────────────────┴─────────────────┴──────┐ │
│  │               KadUDPListener                   │ │
│  │          (Network.framework, UDP)               │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## Referencias

- [KadRoutingTable](02-routing-table.md) — tabla Kademlia
- [KadSearchManager](03-search-manager.md) — búsquedas activas
- [KadUDPListener](04-udp-listener.md) — listener UDP
- [ED2K Protocol Overview](../02-protocols/01-ed2k-overview.md) — contexto de red
