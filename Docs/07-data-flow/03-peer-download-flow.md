# Flujo de Descarga Peer-to-Peer

## Ciclo Completo de Descarga

```
Usuario añade enlace ed2k://
         │
         ▼
Core añade transferencia a CoreTransferStore
         │
         ▼
┌─ ¿Conectado a servidor? ─┐
│         Sí                │ No
│         ▼                 │
│   send GetSources         │
│   ┌──────┴──────┐        │
│   │  Servidor   │        │
│   │  responde   │        │
│   │ foundSources│        │
│   └──────┬──────┘        │
│          ▼               │
└──────────┴───────────────┘
           │
           ▼
   Core conecta a peer vía ED2KPeerTCPConnection
           │
           ▼
         Handshake
    hello / helloAnswer
           │
           ▼
    Solicita hashset
   hashSetRequest → hashSetAnswer
           │
           ▼
   CoreRarityScheduler calcula
     rangos faltantes
           │
           ▼
    Solicita parte (requestParts)
           │
           ▼
    Peer envía parte (sendingPart)
           │
           ▼
  Core escribe bloque via writeBlock
         → CoreTransferStore
           │
           ▼
   Verifica hash del chunk
           │
    ┌──────┴──────┐
    │ ¿Completo?  │
    └──────┬──────┘
        Sí │
           ▼
  Promoción atómica a Incoming/
           │
           ▼
       Repite hasta
     completar archivo
```

## 1. Añadir enlace

El usuario añade un enlace `ed2k://` → `MacMuleStore.addED2KLink()` → RPC `add_ed2k_link` → `CoreTransferStore` crea transferencia en estado `.queued`.

## 2. Obtener fuentes

Si hay conexión a servidor: envía `GetSources` con el hash del archivo. Servidor responde con `foundSources` conteniendo IP:puerto de peers.

Si no hay servidor: busca fuentes via Kad (`kad_search_sources`).

## 3. Conectar a peer

`ED2KPeerTCPConnection` conecta vía TCP al peer:

```swift
// Handshake
→ hello (protocolo, version, userHash, clientID)
← helloAnswer (protocolo, version, userHash, serverIP, serverPort)
```

## 4. Solicitar hashset

```swift
→ setRequestFileID(fileHash)
← hashSetAnswer(hashSet: [MD4hashes])
```

## 5. Planificar rarity

`CoreRarityScheduler` analiza qué partes del archivo faltan y cuáles están disponibles en el peer. Prioriza partes de baja disponibilidad (rarest first).

## 6. Solicitar y recibir partes

```swift
→ requestParts(partNumber: offset: length:)
← sendingPart(data: blockData)
```

## 7. Escribir bloque

`writeBlock` escribe datos en el `.part` file en `Temp/` y actualiza `CoreTransferStore`.

## 8. Verificar chunk

Cada chunk de 9.5MB se verifica contra su hash MD4. Si el hash coincide, el chunk se marca como completo.

## 9. Promover a Incoming/

Cuando todos los chunks están verificados:

1. Archivo `.part` se mueve atómicamente a `Incoming/`
2. Transferencia pasa a estado `.completed`
3. Si `shareCompletedDownloads` está activo, se comparte en la red

## Paralelización

- Hasta **2 peers simultáneos** por descarga
- Cada peer reserva rangos específicos
- Si un peer falla → failover a otro source
- Cooldown de 30s para peers que fallaron
- **Source Exchange**: peers intercambian fuentes entre sí (eMule extension)

## Diagrama de Rangos

```
Archivo: 100 MB
Chunks:  0     1     2     3     4     5     6     7     8     9
        [=====] [     ] [=====] [=====] [     ] [     ] [=====] [     ] [=====] [     ]
Peer A:  └───────────────────────────────┘
Peer B:        └───────────────────────────────────────┘
Legend: [=====] = completo, [     ] = faltante
```

## CoreRarityScheduler

Analiza disponibilidad de partes entre todos los peers conectados:

- Partes con menos peers → mayor prioridad
- Evita descargar la misma parte de múltiples peers
- Reserva rangos para evitar duplicación

## Referencias

- [App to Daemon](01-app-to-daemon.md) — comunicación RPC
- [Daemon to Network](02-daemon-to-network.md) — red del daemon
- [Persistence](04-persistence.md) — almacenamiento de archivos
