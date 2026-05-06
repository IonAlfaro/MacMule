# Formato de Paquetes eD2k TCP

## Sistema de Paquetes

Todos los paquetes eD2k comparten una estructura común implementada por `ED2KPacket` en `ED2KProtocol.swift`.

## Protocol Byte

El primer byte del paquete identifica el protocolo:

```swift
public enum ED2KProtocolByte: UInt8 {
    case edonkey = 0xE3   // Protocolo eDonkey original
    case emule   = 0xC5   // Extensiones eMule
}
```

- `0xE3` — usado para servidores y peers eDonkey original
- `0xC5` — usado para características extendidas de eMule (source exchange, compressed parts, etc.)

## Estructura de `ED2KPacket`

```
┌─────────┬──────────┬────────┬──────────────────┐
│ Proto   │  Size    │ Opcode │     Payload      │
│ (1 byte)│(4 bytes) │(1 byte)│   (Size-1 bytes) │
└─────────┴──────────┴────────┴──────────────────┘
```

```swift
public struct ED2KPacket {
    public var protocolByte: ED2KProtocolByte   // 0xE3 o 0xC5
    public var opcode: UInt8                    // código de operación
    public var payload: Data                    // datos del paquete
}
```

- **Proto**: `0xE3` (eDonkey) o `0xC5` (eMule)
- **Size**: entero de 32 bits little-endian que indica `payload.count + 1`
- **Opcode**: código de operación del paquete
- **Payload**: datos específicos del mensaje

### Codificación (escritura)

```swift
public func encoded() -> Data {
    var data = Data()
    data.append(protocolByte.rawValue)
    data.appendLittleEndian(UInt32(payload.count + 1))
    data.append(opcode)
    data.append(payload)
    return data
}
```

### Decodificación (lectura)

```swift
public static func decode(_ data: Data) throws -> ED2KPacket
```

El decodificador verifica:
1. Tamaño mínimo de 5 bytes (header)
2. Protocol byte soportado
3. `declaredSize >= 1` (contiene opcode)
4. Coincidencia exacta entre `declaredSize + 5` y `data.count`
5. Descompresión si el protocol byte es `0xD4`

## Paquetes Comprimidos

Cuando el protocol byte es `0xD4`, el payload viene comprimido con zlib:

```swift
private enum ED2KPackedPacketDecoder {
    static let protocolByte: UInt8 = 0xD4
    // Descomprime y retorna con protocol byte 0xE3
}
```

- Límite seguro: 250,000 bytes tras descompresión
- Usa `macmule_zlib_inflate()` del módulo `MacMuleZlib`

## ED2KPacketStreamDecoder

Procesa un flujo TCP continuo (pueden llegar múltiples paquetes encadenados o parciales):

```swift
public struct ED2KPacketStreamDecoder {
    private var buffer = Data()

    public mutating func append(_ data: Data) throws -> [ED2KPacket]
}
```

```
Flujo TCP entrante:
┌──────────┬──────────┬──────────┐
│ Packet 1 │ Packet 2 │ Packet 3 │ ...
└──────────┴──────────┴──────────┘

El decoder bufferiza datos parciales y extrae
paquetes completos iterativamente:
1. Lee header de 5 bytes
2. Calcula tamaño total
3. Si buffer contiene el paquete completo → extrae
4. Sino → espera más datos
```

## Opcodes — Servidor (`ED2KPacketOpcode`)

| Opcode | Nombre | Dirección | Descripción |
|--------|--------|-----------|-------------|
| `0x01` | `loginRequest` | C → S | Login del cliente |
| `0x15` | `offerFiles` | C → S | Publicar archivos compartidos |
| `0x16` | `search` | C → S | Búsqueda por palabra clave |
| `0x19` | `getSources` | C → S | Solicitar fuentes de un archivo |
| `0x1C` | `callbackRequest` | C → S | Solicitar callback a un peer |
| `0x32` | `serverList` | S → C | Lista de servidores conocidos |
| `0x33` | `searchResults` | S → C | Resultados de búsqueda |
| `0x34` | `serverStatus` | S → C | Estado del servidor (usuarios/archivos) |
| `0x35` | `callbackRequested` | S → C | Un peer solicita conexión |
| `0x36` | `callbackFailed` | S → C | Falló el callback |
| `0x38` | `serverMessage` | S → C | Mensaje del servidor |
| `0x40` | `idChange` | S → C | Asignación de clientID |
| `0x41` | `serverIdent` | S → C | Identidad del servidor |
| `0x42` | `foundSources` | S → C | Fuentes encontradas |
| `0x44` | `foundSourcesObfuscated` | S → C | Fuentes con ofuscación |

## Opcodes — Peer (`ED2KPeerPacketOpcode`)

| Opcode | Nombre | Dirección | Descripción |
|--------|--------|-----------|-------------|
| `0x01` | `hello` | A ↔ B | Handshake de saludo |
| `0x4C` | `helloAnswer` | A ↔ B | Respuesta al handshake |
| `0x40` | `compressedPart` | A ↔ B | Parte comprimida (32-bit) |
| `0x46` | `sendingPart` | A ↔ B | Envío de parte (32-bit) |
| `0x47` | `requestParts` | A → B | Solicitar partes (32-bit) |
| `0x48` | `fileRequestAnswerNoFile` | B → A | Archivo no disponible |
| `0x4F` | `setRequestFileID` | A → B | Seleccionar archivo a descargar |
| `0x50` | `fileStatus` | A ↔ B | Estado del archivo |
| `0x51` | `hashSetRequest` | A → B | Solicitar hashset de partes |
| `0x52` | `hashSetAnswer` | B → A | Respuesta con hashset |
| `0x54` | `startUploadRequest` | A → B | Solicitar inicio de subida |
| `0x55` | `acceptUploadRequest` | B → A | Aceptar subida |
| `0x58` | `requestFileName` | A → B | Solicitar nombre de archivo |
| `0x5C` | `queueRank` | B → A | Posición en cola de espera |
| `0x81` | `requestSources` | A → B | Solicitar fuentes (v1) |
| `0x82` | `answerSources` | B → A | Fuentes disponibles (v1) |
| `0x83` | `requestSources2` | A → B | Solicitar fuentes (v2, eMule) |
| `0x84` | `answerSources2` | B → A | Fuentes disponibles (v2, eMule) |
| `0xA1` | `compressedPartI64` | A ↔ B | Parte comprimida (64-bit) |
| `0xA2` | `sendingPartI64` | A ↔ B | Envío de parte (64-bit) |
| `0xA3` | `requestPartsI64` | A → B | Solicitar partes (64-bit) |

## Tag Encoding

Los metadatos se transportan como `ED2KTag`:

```swift
public struct ED2KTag {
    public var name: UInt8     // identificador del tag
    public var value: ED2KTagValue  // valor
}
```

### Tipos de valor (`ED2KTagValue`)

```swift
public enum ED2KTagValue {
    case string(String)       // type 0x02
    case uint8(UInt8)         // type 0x09
    case uint16(UInt16)       // type 0x08
    case uint32(UInt32)       // type 0x03
    case uint64(UInt64)       // type 0x0B
}
```

### Formato codificado

```
┌──────┬──────┬──────┬──────────┐
│ Type │ Name │ Tag  │  Value   │
│(1byt)│ Len  │ Name │          │
│      │(2byt)│(1byt)│          │
└──────┴──────┴──────┴──────────┘
```

- **Type**: tipo del valor (0x02 string, 0x03 uint32, etc.)
- **Name Len/Name**: si type < 0x80, Name Len es el largo del nombre; si type & 0x80 != 0, el nombre es de 1 byte
- **Value**: datos del valor (longitud variable según el tipo)

### Tags comunes de búsqueda

```swift
public enum ED2KSearchTagName {
    public static let fileName: UInt8 = 0x01
    public static let fileSize: UInt8 = 0x02
    public static let sources: UInt8 = 0x15
    public static let completeSources: UInt8 = 0x30
}
```

## Codificación de Enteros

Todos los valores numéricos multi-byte se codifican en **little-endian**:

```swift
// Ejemplo de extensión de Data
data.appendLittleEndian(UInt32(value))  // 4 bytes LE
data.appendLittleEndian(UInt16(value))  // 2 bytes LE
data.appendLittleEndian(UInt64(value))  // 8 bytes LE
```

## ED2KBinaryReader

Helper interno para lectura ordenada de paquetes:

```swift
struct ED2KBinaryReader {
    var data: Data
    var offset = 0

    mutating func readUInt8() throws -> UInt8
    mutating func readUInt16LittleEndian() throws -> UInt16
    mutating func readUInt32LittleEndian() throws -> UInt32
    mutating func readUInt64LittleEndian() throws -> UInt64
    mutating func readData(count: Int) throws -> Data
    mutating func readBytes(count: Int) throws -> [UInt8]
}
```

## Enlaces

- [01: Visión General de eD2k](01-ed2k-overview.md)
- [03: Sesiones con Servidor](03-server-session.md)
- [04: Sesiones Peer-to-Peer](04-peer-session.md)
- `ED2KProtocol.swift` — Definición completa del sistema de paquetes
