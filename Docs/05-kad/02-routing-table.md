# KadRoutingTable — Tabla de Routing Kademlia

`MacMuleCore/Sources/MacMuleCore/KadRoutingTable.swift` (182 líneas)
`MacMuleCore/Sources/MacMuleCore/KadRoutingBin.swift` (78 líneas)

## Descripción

Implementación de la tabla de routing Kademlia. Mantiene una lista de **buckets** (`KadRoutingBin`) que almacenan contactos de nodos conocidos.

## Self Node ID

El `selfNodeID` es un `KadUInt128` (entero de 128 bits) generado aleatoriamente. Identifica de forma única a este nodo en la red Kad.

```
selfNodeID = KadUInt128(random: )  ← 128 bits aleatorios
```

## KadRoutingBin

Cada bucket tiene:

- `depth`: profundidad del bucket (bits de prefijo compartido)
- `contacts: [KadContact]`: hasta `k` contactos (k = 10)
- `lastChanged: Date`: timestamp de última modificación

```swift
public struct KadRoutingBin: Equatable, Sendable, Codable {
    public var contacts: [KadContact]
    public var lastChanged: Date
    public var depth: Int
}
```

### Inserción

La inserción sigue las reglas Kademlia:

1. Si el nodo ya existe → actualizar y mover al frente
2. Si hay espacio → insertar al inicio
3. Si el bucket está lleno → reemplazar el contacto más antiguo si está expirado
4. Si todos los contactos están vivos → rechazar (`rejectedBucketFull`)

## Métodos Principales

| Método | Descripción |
|--------|-------------|
| `addContact(_:)` | Inserta/actualiza contacto en el bucket correspondiente |
| `removeContact(nodeID:)` | Elimina contacto por nodeID |
| `closestContacts(to:maxCount:)` | Retorna los k contactos más cercanos a un target |
| `findContact(nodeID:)` | Busca un contacto por nodeID |
| `allContacts()` | Todos los contactos conocidos |
| `expireStale()` | Elimina contactos expirados |
| `bucketStats(for:)` | Estadísticas de buckets para UI |

## Split de Buckets

Cuando un bucket se llena y no es el último, se divide en dos:

```swift
private func splitBucketIfNeeded(at index: Int) {
    // Crea bucketA y bucketB con depth+1
    // Distribuye contactos según el bit en posición depth
}
```

## Maintenance Timer

Se ejecuta periódicamente para:

1. Eliminar contactos expirados (`expireStale`)
2. Refrescar buckets poco usados
3. Buscar nodos en buckets vacíos

## Referencias

- [Kad Overview](01-overview.md) — visión general
- [KadSearchManager](03-search-manager.md) — búsquedas
- [KadUDPListener](04-udp-listener.md) — comunicación UDP
