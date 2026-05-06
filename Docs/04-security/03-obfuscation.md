# CoreObfuscationLayer — Ofuscación de Protocolo

`MacMuleCore/Sources/MacMuleCore/CoreObfuscationLayer.swift` (146 líneas)

## Descripción

Capa de ofuscación de protocolo compatible con eMule. Usa **CommonCrypto** con cifrado **RC4** para ofuscar el tráfico eD2k, evadiendo ISP que estrangulan tráfico P2P por inspección profunda de paquetes (DPI).

## CommonCrypto

Bridge directo a `CC_cryptor.h`:

- `CCCryptorCreate` con `kCCAlgorithmRC4`
- `CCCryptorUpdate` para cifrado/descifrado continuo
- `CCCryptorRelease` para limpieza

## API

```swift
public final class CoreObfuscationLayer: @unchecked Sendable {
    public func startEncryption(key: Data)       // inicia cifrado con clave RC4
    public func startDecryption(key: Data)       // inicia descifrado con clave RC4
    public func process(_ data: Data) -> Data    // procesa datos (cifra/descifra)
    public func processInPlace(_ data: inout Data)
    public func reset()                          // libera el cryptor
}
```

## Estados de Cifrado

```
startEncryption(key:) → cryptor creado con kCCEncrypt
                         ↓
              process(data) → CCCryptorUpdate
                         ↓
                   reset() / deinit
```

## Generación de Clave RC4

```swift
public static func createObfuscationKey(userHash: Data, challenge: Data) -> Data
```

Deriva clave vía MD4(userHash + challenge) como en la especificación de ofuscación de eMule. Incluye implementación manual de **MD4** (86 líneas) con las rondas estándar:

```
Round 1: f = (b & c) | (~b & d)
Round 2: f = (b & c) | (b & d) | (c & d)
Round 3: f = b ^ c ^ d
Round 4: f = c ^ (b | ~d)
```

## Thread Safety

Usa `NSLock` para proteger el acceso al `CCCryptorRef` compartido.

## Referencias

- [CoreSecureIdent](02-secure-ident.md) — identidad segura
- [CoreIPFilter](01-ip-filter.md) — filtro de IP
- [ED2K Protocol Overview](../02-protocols/01-ed2k-overview.md) — contexto de la red
