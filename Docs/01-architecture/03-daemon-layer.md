# Capa del Daemon — macmule-core-daemon

## ¿Qué es?

`macmule-core-daemon` es un ejecutable independiente construido con SwiftPM. Es el puente entre la UI (MacMule.app) y el motor de protocolo (MacMuleCore). Se ejecuta como un proceso separado y se comunica con la app mediante JSON-RPC 2.0.

## Comunicación

La app y el daemon se comunican de dos formas:

1. **Unix socket (AF_UNIX, SOCK_STREAM)** — modo preferido, activado con `--socket <path>`
2. **stdin/stdout** — fallback: el daemon lee líneas JSON de stdin y escribe respuestas JSON a stdout

### Formato JSON-RPC

Definido en `MacMuleCore/Sources/MacMuleCore/CoreRPC.swift:3`:

```json
{"jsonrpc":"2.0","id":1,"method":"snapshot","params":{}}
```

Respuesta:
```json
{"jsonrpc":"2.0","id":1,"result":{...}}
```

## CoreSocketServer

`MacMuleCore/Sources/MacMuleCore/CoreSocketServer.swift:27` — Escucha en un socket Unix:

```
┌──────────────────────────────────────────────────┐
│ CoreSocketServer                                 │
│                                                  │
│ 1. socket(AF_UNIX, SOCK_STREAM, 0)              │
│ 2. bind(sockaddr_un)                             │
│ 3. listen(fd, 5)                                 │
│ 4. accept() → client fd                          │
│ 5. read() → JSON RPC request                     │
│ 6. CoreRPCHandler.handle(data) → Data           │
│ 7. write(response)                               │
│ 8. close(client)                                 │
│ 9. goto 4                                        │
└──────────────────────────────────────────────────┘
```

El socket se crea en:
- `~/Library/Application Support/MacMule/Core/macmule-core.sock` (con `--storage`)
- O en `/tmp/macmule-core-<PID>-0.sock` (sin `--storage`)

## CLI del Daemon

`MacMuleCore/Sources/MacMuleCoreDaemon/main.swift:5-103`

```
macmule-core-daemon [--socket <path>] [--storage <dir>] [--incoming-dir <dir>] [--temp-dir <dir>]
```

| Flag | Propósito |
|---|---|
| `--socket <path>` | Ruta del Unix socket a escuchar |
| `--storage <dir>` | Directorio raíz para persistencia del core |
| `--incoming-dir <dir>` | Directorio donde se guardan descargas completadas |
| `--temp-dir <dir>` | Directorio para archivos parciales (`.part`) |

Si no se especifica `--storage`, usa `~/Library/Application Support/MacMule/Core/`.

## CoreRPCHandler

`MacMuleCore/Sources/MacMuleCore/CoreRPC.swift` — Traduce peticiones JSON-RPC a llamadas a `MacMuleCoreService`:

| RPC | Acción |
|---|---|
| `snapshot` | Devuelve estado completo (descargas, subidas, servidores, Kad, estadísticas) |
| `events(after:)` | Eventos incrementales desde un timestamp |
| `search(query:)` | Búsqueda eD2k/Kad |
| `addDownload(from:)` | Agregar descarga desde resultado de búsqueda |
| `addED2KLink(_:)` | Agregar descarga desde link ed2k:// |
| `setDownloadPaused(id:paused:)` | Pausar/reanudar descarga |
| `removeDownload(id:)` | Eliminar descarga |
| `setConnection(enabled:)` | Conectar/desconectar de la red |
| `connectToServer(host:port:)` | Conectar a servidor específico |
| `addServer(host:port:)` | Agregar servidor a la lista |
| `removeServer(host:port:)` | Remover servidor de la lista |
| `importServers(servers:)` | Importar lista de servidores |
| `setConfig(maxDownloadKilobytes:maxUploadKilobytes:)` | Límites de ancho de banda |
| `kadStart/kadStop` | Iniciar/detener red Kad |
| `kadBootstrap(host:port:)` | Bootstrap de nodo Kad |
| `kadSearchKeyword(query:)` | Búsqueda por keyword en Kad |
| `kadSearchSources(hash:)` | Búsqueda de fuentes por hash |
| `restartCore` | Reiniciar el core |
| `schedulerEnable/enableEntry/...` | Gestión del scheduler |
| `addCategory/removeCategory` | Gestión de categorías |

## MacMuleDaemonLauncher

`MacMule/MacMuleDaemonLauncher.swift:214` — Ubica y lanza el daemon desde la app.

### Orden de búsqueda del binario

1. `MACMULE_CORE_DAEMON_PATH` (env var, para debugging)
2. En DEBUG: `.build/debug/macmule-core-daemon` (desarrollo)
3. `MacOS/macmule-core-daemon` (junto al .app, ruta de producción)
4. `Bundle.main.url(forAuxiliaryExecutable:)`
5. `Bundle.main.url(forResource:)`
6. En RELEASE: `.build/debug/...` como último recurso

### Flujo de lanzamiento

```
MacMuleStore.start()
  │
  ├─ ¿MACMULE_CORE_SOCKET definida?
  │   └─ Sí → DaemonMacMuleCoreClient(socketPath)
  │
  └─ No → EmptyMacMuleCoreClient (placeholder inmediato)
          └─ (async) MacMuleDaemonLauncher.launchBundledDaemonAsync()
               ├─ forceFresh → pkill -x macmule-core-daemon
               ├─ attachToExistingDaemon → probar socket existente
               ├─ buscar binario en candidatos
               ├─ Process() con --socket, --storage, --incoming-dir, --temp-dir
               ├─ waitForSocket (timeout 2s, pooling 50ms)
               └─ DaemonMacMuleCoreClient(socketPath, session)
```

### MacMuleDaemonSession

`MacMule/MacMuleDaemonLauncher.swift:6` — Ciclo de vida del daemon:

- Inicializa `Process` con pipes para stdout/stderr
- Observa logs del daemon (máximo 200 entradas)
- En `deinit` o `stop()`: termina el proceso, limpia el socket
- Modo `attachedTo` para conectarse a un daemon ya existente (sin ownership)

## Preferencia de Conexión

La app sigue este orden de preferencia:

1. `MACMULE_CORE_SOCKET` — Variable de entorno para socket externo (útil en debugging o deployments)
2. **Bundled daemon** — `macmule-core-daemon` dentro del .app (`MacOS/`)
3. **In-memory fallback** — `EmptyMacMuleCoreClient` (placeholder vacío hasta que el daemon esté listo)

## Referencias

- [Visión General](01-overview.md)
- [Capa de Aplicación](02-app-layer.md)
- [Paquete MacMuleCore](04-core-package.md)
