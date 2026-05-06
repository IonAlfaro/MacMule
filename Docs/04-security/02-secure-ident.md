# CoreSecureIdent — Identidad Segura

`MacMuleCore/Sources/MacMuleCore/CoreSecureIdent.swift` (40 líneas)

## Descripción

Sistema de identidad segura basado en **Curve25519** (X25519) usando **CryptoKit**. Genera un par de llaves pública/privada para firmar datos y verificar identidades de peers. Reemplaza el sistema de firma con SHA-1 de eMule.

## CryptoKit

Apple CryptoKit proporciona las primitivas:

- `Curve25519.Signing.PrivateKey` — clave privada para firmar
- `Curve25519.Signing.PublicKey` — clave pública para verificar
- `SHA256.hash(data:)` — hash de los datos antes de firmar

## API

```swift
public final class CoreSecureIdent: @unchecked Sendable {
    public let publicKeyData: Data

    public init()                                    // genera nuevo par aleatorio
    public init(privateKeyData: Data) throws        // restaura desde clave persistida
    public func sign(_ data: Data) -> Data           // SHA256 + firma Ed25519
}
```

Métodos estáticos:

```swift
public static func verify(signature: Data, data: Data, publicKeyData: Data) -> Bool
public static func generateKeyPair() -> (privateKey: Data, publicKey: Data)
public static func computeSharedSecret(privateKeyData: Data, publicKeyData: Data) throws -> Data
```

## Persistencia

La clave privada se guarda en `Data` (raw representation) y puede persistirse via `CoreStorageDirectory + "/identity.pem"`. Se restaura con `init(privateKeyData:)`.

```
Core/
├── identity.pem           # clave privada Curve25519
├── Temp/                  # .part files
└── credits.json           # CoreCreditsList
```

## Flujo de Firma

1. Hash del mensaje con SHA-256
2. Firma del hash con clave privada Ed25519
3. El receptor verifica con `verify(signature:data:publicKeyData:)`

## Referencias

- [CoreIPFilter](01-ip-filter.md) — filtro de rangos IP
- [CoreObfuscationLayer](03-obfuscation.md) — ofuscación de protocolo
- [Peer Download Flow](../07-data-flow/03-peer-download-flow.md) — uso en handshake
