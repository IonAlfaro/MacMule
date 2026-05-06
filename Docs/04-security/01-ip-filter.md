# CoreIPFilter — Filtro de Rangos IP

`MacMuleCore/Sources/MacMuleCore/CoreIPFilter.swift` (95 líneas)

## Descripción

Filtro de rangos IP para bloquear tráfico de redes no deseadas (spyware, ISP maliciosos, geolocalización no deseada). Es el equivalente al IPFilter de eMule.

## Archivos de Filtro

Carga archivos con una entrada por línea en dos formatos:

```
1.2.3.4 - 5.6.7.8   # rango simple
10.0.0.0/8           # CIDR
192.168.1.1          # IP única
```

Líneas vacías o con prefijo `#` se ignoran.

## Thread Safety

Usa `NSLock` para proteger el array de rangos. Todo el acceso a `ranges` pasa por `lock.lock()` / `lock.unlock()`.

```swift
public final class CoreIPFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var ranges: [IPRange] = []
}
```

## API Pública

| Método | Descripción |
|--------|-------------|
| `load(from url: URL)` | Carga archivo de filtro, parsea líneas en `IPRange` |
| `isBlocked(ip: String) -> Bool` | Verifica si una IP (formato "x.x.x.x") está bloqueada |
| `blockedCount -> Int` | Número total de rangos bloqueados |

## IPRange

```swift
public struct IPRange: Equatable, Sendable {
    public let start: UInt32
    public let end: UInt32
}
```

Soporta `contains(ip:)` con búsqueda binaria implícita (`ranges.contains`). La función auxiliar `ipv4ToUInt32` convierte cadenas IPv4 a `UInt32` para comparación rápida.

## Parseo CIDR

Para CIDR calcula `network = ip & mask` y `broadcast = network | ~mask`, creando un `IPRange` desde network a broadcast.

## Referencias

- [CoreSecureIdent](02-secure-ident.md) — identidad segura con Curve25519
- [CoreObfuscationLayer](03-obfuscation.md) — ofuscación de protocolo
- [CoreCreditsList](04-credits.md) — sistema de créditos
