# KadUDPListener — Escucha/Sender UDP

`MacMuleCore/Sources/MacMuleCore/KadUDPListener.swift` (152 líneas)

## Descripción

Listener UDP para la red Kad usando **Network.framework** (`NWListener`). Escucha en un puerto UDP configurable, recibe paquetes Kad entrantes y los envía a `KadPacketHandler`.

## Network.framework

Usa `NWParameters.udp` con `allowLocalEndpointReuse = true` para permitir múltiples conexiones.

## API

```swift
public final class KadUDPListener: @unchecked Sendable {
    public private(set) var isListening: Bool
    public private(set) var boundPort: UInt16

    public func setPacketHandler(_ handler: any KadUDPPacketHandler)
    public func start(port: UInt16) throws
    public func stop()
    public func sendPacket(_ data: Data, to endpoint: KadEndpoint)
}
```

### KadUDPPacketHandler Protocol

```swift
public protocol KadUDPPacketHandler: AnyObject, Sendable {
    func handleKadPacket(_ data: Data, from endpoint: KadEndpoint)
}
```

## Flujo de Recepción

```
NWListener.start(port:)
  ↓
stateUpdateHandler(.ready)
  ↓
newConnectionHandler → NWConnection.start()
  ↓
receiveMessage → extractEndpoint(from:)
  ↓
packetHandler.handleKadPacket(data, from: endpoint)
```

## Flujo de Envío

```
sendPacket(data, to: endpoint)
  ↓
NWConnection(host:port:, using: .udp)
  ↓
connection.send(content: data)
  ↓
.contentProcessed → connection.cancel()
```

## KadEndpoint

`MacMuleCore/Sources/MacMuleCore/KadContact.swift` — struct con `ipAddress: String` y `port: UInt16`.

## Thread Safety

Usa `DispatchQueue(label: "com.macmule.kad.udp", qos: .utility)` para toda la operación del listener. El `packetHandler` se protege con `NSLock`.

## Referencias

- [Kad Overview](01-overview.md) — visión general
- [KadRoutingTable](02-routing-table.md) — tabla Kademlia
- [KadSearchManager](03-search-manager.md) — búsquedas
