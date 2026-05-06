# KadSearchManager — Gestor de Búsquedas Kad

`MacMuleCore/Sources/MacMuleCore/KadSearchManager.swift` (168 líneas)
`MacMuleCore/Sources/MacMuleCore/KadLookupCoordinator.swift` (118 líneas)

## Descripción

Maneja las búsquedas activas en la red Kad. Dos componentes principales:

- **KadSearchManager**: gestiona búsquedas de keywords y fuentes
- **KadLookupCoordinator**: coordinación de búsqueda paralela de nodos

## KadSearchManager

```swift
public final class KadSearchManager: @unchecked Sendable {
    public func startSearch(id:type:target:searchTerms:) -> KadActiveSearch
    public func addResults(_ results: [KadSearchResultItem], to searchID: KadUInt128)
    public func addClosestContacts(_ contacts: [KadContact], to searchID: KadUInt128)
    public func completeSearch(_ searchID: KadUInt128)
    public func removeSearch(_ searchID: KadUInt128)
    public func expireStaleSearches() -> [KadUInt128]
}
```

### KadActiveSearch

```swift
public struct KadActiveSearch: Equatable, Sendable, Codable {
    public var id: KadUInt128
    public var type: KadSearchType        // .keyword, .fileSources
    public var target: KadUInt128
    public var startedAt: Date
    public var completedAt: Date?
    public var results: [KadSearchResultItem]
    public var queriedNodes: Int
}
```

### KadSearchResultItem

```swift
public struct KadSearchResultItem: Equatable, Sendable, Codable {
    public var fileHash: Data
    public var fileName: String
    public var fileSize: UInt64
    public var sourceID: KadUInt128?
    public var sourceIP: String?
    public var sourcePort: UInt16?
}
```

## KadLookupCoordinator

Búsqueda recursiva de nodos cercanos a un target:

```
findNodes(target:) → 1. Obtener α contactos iniciales de routing table
                     2. Enviar find_node a cada uno en paralelo
                     3. Esperar respuestas (~3s)
                     4. Agregar nuevos contactos recibidos
                     5. Enviar find_node a los α más cercanos no consultados
                     6. Repetir hasta converger
                     7. Retornar k contactos más cercanos
```

α (alpha) es el factor de paralelismo (KadConstants.alpha).

## Tipos de Búsqueda

- **Keyword search**: busca archivos por palabras clave en la DHT
- **Source search**: busca peers que tienen un archivo específico por hash
- **Node lookup**: encuentra los k nodos más cercanos a un ID

## Referencias

- [Kad Overview](01-overview.md) — visión general
- [KadRoutingTable](02-routing-table.md) — tabla Kademlia
- [KadUDPListener](04-udp-listener.md) — comunicación UDP
