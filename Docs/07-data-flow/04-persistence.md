# Persistencia en MacMule

## Sistema de Archivos

Todo se almacena en `~/Library/Application Support/MacMule/`:

```
~/Library/Application Support/MacMule/
├── Core/
│   ├── Temp/                        # Archivos .part (datos parciales)
│   ├── identity.pem                 # Clave privada Curve25519
│   ├── credits.json                 # CoreCreditsList
│   ├── nodes.dat                    # Nodos Kad conocidos
│   ├── server.met                   # Lista de servidores importados
│   ├── settings.json                # Configuración del daemon
│   ├── scheduler.json               # Programación del scheduler
│   └── filters/                     # Archivos IP filter
│       └── ipfilter.dat
├── settings.plist                   # UserDefaults (app layer)
└── Downloads/
    └── MacMule/                     # Directorio de descargas (default)
        └── Incoming/                # Archivos completados
```

## Sidecar JSON

Por cada transferencia activa, un archivo sidecar `.json` guarda metadatos:

```
Temp/<hash>.part          # datos parciales
Temp/<hash>.part.json     # metadatos (nombre, hash, progreso, fuentes)
```

## .part Files

Los archivos `.part` siguen el formato eMule:

- Extensión `.part` mientras la descarga está en curso
- Datos brutos del archivo, con agujeros para partes no descargadas
- Tamaño fijo desde el inicio

## Promoción Atómica

Cuando una descarga se completa:

1. Se verifica el hash MD4 del archivo completo
2. Se renombra atómicamente (`FileManager.moveItem`) de `Temp/` a `Incoming/`
3. Se elimina el sidecar `.json`
4. Transferencia marca `.completed`

## nodes.dat

Formato binario con nodos Kad conocidos:

- Dirección IP (4 bytes)
- Puerto UDP (2 bytes)
- Node ID (16 bytes)
- Timestamp de último contacto

Se usa para bootstrap rápido al iniciar Kad.

## server.met

Lista de servidores eD2k importados. Parseable via `ServerMetParser`. Almacena:

- Host:Puerto
- Nombre
- Descripción
- Usuarios/Archivos (cached)

## Persistencia de Settings

### App Layer (UserDefaults)

```
UserDefaults.standard:
  ├── downloadDirectory
  ├── tempDirectory
  ├── maxDownloadKilobytes
  ├── maxUploadKilobytes
  ├── autoConnect
  ├── nickname
  ├── tcpPort
  ├── udpPort
  ├── enableKad
  ├── enableUPnP
  └── ...
```

### Daemon Layer (settings.json)

```
Core/settings.json:
  ├── maxDownloadKilobytes
  ├── maxUploadKilobytes
  ├── schedulerEnabled
  └── ...
```

## Crash Recovery

El sistema de **resume checkpoint** permite recuperación ante crashes:

1. Antes de escribir un bloque, se guarda checkpoint atómico
2. Si el proceso muere, al reiniciar se escanean `.part` files
3. Se comparan hashes de chunks contra el sidecar
4. Chunks corruptos se marcan como pendientes

```
Crash → restart → scan Temp/*.part
         ↓
   compare chunk hashes
         ↓
   chunks OK → continue download
   chunks corrupt → re-download
```

## Codable

Toda la persistencia usa `Codable`:

```swift
let data = try JSONEncoder().encode(records)
try data.write(to: url, options: .atomic)
```

## Referencias

- [Peer Download Flow](03-peer-download-flow.md) — escritura de bloques
- [CoreCreditsList](../04-security/04-credits.md) — créditos
- [CoreSecureIdent](../04-security/02-secure-ident.md) — identidad persistida
