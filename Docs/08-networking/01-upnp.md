# UPnPPortMapper — Mapeo Automático de Puertos via UPnP

`MacMuleCore/Sources/MacMuleCore/UPnPPortMapper.swift` (564 líneas)

## Descripción

Mapeo automático de puertos TCP/UDP usando **UPnP IGD** (Internet Gateway Device Protocol). Permite que MacMule sea accesible desde internet sin configuración manual del router.

## Protocolo

1. **SSDP Discovery**: envía `M-SEARCH` a `239.255.255.250:1900`
2. **Descripción del dispositivo**: parsea XML del router
3. **SOAP AddPortMapping**: envía petición al control URL

```
M-SEARCH * HTTP/1.1
HOST: 239.255.255.250:1900
MAN: "ssdp:discover"
MX: 2
ST: urn:schemas-upnp-org:service:WANIPConnection:1
```

## API

```swift
public protocol ED2KPeerPortMapper: AnyObject {
    func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    )
}
```

### UPnPPortMappingResult

```swift
public struct UPnPPortMappingResult: Equatable, Sendable {
    public var tcpMapped: Bool
    public var udpMapped: Bool
    public var detail: String
}
```

## SOAP Request

```xml
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:AddPortMapping xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
      <NewRemoteHost></NewRemoteHost>
      <NewExternalPort>4662</NewExternalPort>
      <NewProtocol>TCP</NewProtocol>
      <NewInternalPort>4662</NewInternalPort>
      <NewInternalClient>192.168.1.100</NewInternalClient>
      <NewEnabled>1</NewEnabled>
      <NewPortMappingDescription>MacMule</NewPortMappingDescription>
      <NewLeaseDuration>0</NewLeaseDuration>
    </u:AddPortMapping>
  </s:Body>
</s:Envelope>
```

## Búsqueda de Router UPnP

1. Envía SSDP discovery a multicast (239.255.255.250:1900)
2. Escucha respuestas con header `LOCATION:`
3. Descarga XML de descripción del dispositivo
4. Busca servicio WANIPConnection o WANPPPConnection
5. Extrae `controlURL` para SOAP calls

## Caché de Puertos

Si los mismos puertos ya fueron mapeados exitosamente, no reenvía la petición UPnP.

```swift
private var lastMappedPorts: PortSet?
```

## Thread Safety

Toda la operación UPnP se ejecuta en una `DispatchQueue` serial. Flag `isMappingInFlight` previene peticiones concurrentes.

## Referencias

- [NAT-PMP](02-nat-pmp.md) — alternativa a UPnP
- [MacMuleStore](../06-app-layer/01-store.md) — enableUPnP setting
- [Daemon to Network](../07-data-flow/02-daemon-to-network.md) — stack de red
