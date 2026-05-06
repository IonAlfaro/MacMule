# NATPMPPortMapper — Mapeo via NAT-PMP

`MacMuleCore/Sources/MacMuleCore/NATPMPPortMapper.swift` (404 líneas)

## Descripción

Implementación de **NAT-PMP** (RFC 6886) para mapeo automático de puertos. Protocolo más simple que UPnP, soportado por muchos routers Apple (AirPort) y otros fabricantes.

## Protocolo

1. Enviar petición UDP al gateway en puerto **5351**
2. Gateway responde con el mapeo creado y puerto externo asignado
3. Renovación periódica según lease duration

```
Cliente                       Gateway (puerto 5351 UDP)
   │                                │
   │  Map TCP 4662 → 4662 (3600s)   │
   ├───────────────────────────────►│
   │  Response: 0=success, epoch=X  │
   │◄───────────────────────────────┤
   │                                │
   │  Map UDP 4672 → 4672 (3600s)   │
   ├───────────────────────────────►│
   │  Response: 0=success, epoch=X  │
   │◄───────────────────────────────┤
```

## API

```swift
public final class NATPMPPortMapper: ED2KPeerPortMapper {
    public func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    )
}
```

## Formato de Petición

```
Byte 0:  Version (0)
Byte 1:  Opcode (1=TCP, 2=UDP)
Byte 2-3: Reserved (0)
Byte 4-5: Internal Port (big-endian)
Byte 6-7: Requested External Port (big-endian)
Byte 8-11: Lifetime in seconds (big-endian, e.g. 3600)
```

## Formato de Respuesta

```
Byte 0:  Version (0)
Byte 1:  Opcode | 0x80
Byte 2-3: Result Code (0=success)
Byte 4-7: Epoch time
Byte 8-9: Internal Port
Byte 10-11: External Port
Byte 12-15: Lifetime
```

## NATPMPResultCode

| Code | Significado |
|------|-------------|
| 0 | Success |
| 1 | Unsupported Version |
| 2 | Not Authorized |
| 3 | Network Failure |
| 4 | Out of Resources |
| 5 | Unsupported Opcode |

## Gateway Discovery

Usa `SystemConfiguration` (`SCDynamicStore`) para obtener la IP del gateway por defecto:

```swift
public static func defaultGatewayIPv4Address() -> String? {
    let store = SCDynamicStoreCreate(...)
    let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4")
    return value["Router"] as? String
}
```

## SequentialPeerPortMapper

Combina múltiples mappers en secuencia (fallback):

```swift
let mapper = SequentialPeerPortMapper(mappers: [
    ("UPnP", UPnPPortMapper()),
    ("NAT-PMP", NATPMPPortMapper()),
])
```

Intenta UPnP primero; si falla, prueba NAT-PMP.

## Cache y Thread Safety

Igual que UPnP: `PortSet` cache y `DispatchQueue` serial.

## Referencias

- [UPnP](01-upnp.md) — alternativa UPnP
- [MacMuleStore](../06-app-layer/01-store.md) — enableUPnP setting
- [Daemon to Network](../07-data-flow/02-daemon-to-network.md) — stack de red
