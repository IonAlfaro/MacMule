# Visión General de MacMule

## ¿Qué es MacMule?

MacMule es un cliente nativo de la red eD2k (eDonkey2000) para macOS, escrito íntegramente en Swift. Su propósito es proveer una alternativa moderna, eficiente y nativa a eMule (originalmente escrito en C++ para Windows) y a clientes legacy como aMule (wxWidgets) o xMule.

MacMule reemplaza la pila cliente-servidor TCP/UDP tradicional con componentes Swift 6 modernos, huye de wxWidgets/Qt/WPF y apuesta por SwiftUI + Combine + async/await en toda la cadena.

## ¿Por qué existe?

- **No hay un cliente eD2k nativo de macOS** — eMule requiere Windows, aMule está abandonado y usa wxWidgets con integración macOS deficiente.
- **SwiftUI moderna** — aprovecha NavigationSplitView, SF Symbols, @EnvironmentObject, y el App Sandbox de macOS.
- **Arquitectura desacoplada** — separa la UI del motor de red para permitir pruebas unitarias y ejecución headless.

## Arquitectura de 3 Capas

```
+-------------------------------------------------------------+
|                        MacMule.app                          |
|  (SwiftUI, macOS 15+, ventana mínima 1020x660)              |
|                                                             |
|  +-------------------------------------------------------+  |
|  | NavigationSplitView |    DetailContainerView           |  |
|  |  - SidebarNavList   |    - 10 vistas (Dashboard,      |  |
|  |  - SidebarStatus    |      Search, Downloads, ...)     |  |
|  |  - ToolbarSearch    |                                  |  |
|  +-------------------------------------------------------+  |
|                      |  JSON-RPC                            |
|                      v  Unix socket                         |
|  +-------------------------------------------------------+  |
|  |              macmule-core-daemon                       |  |
|  |  (SwiftPM executable, proceso independiente)           |  |
|  |                                                       |  |
|  |  CoreSocketServer (Unix socket listener)              |  |
|  |  CoreRPCHandler (JSON-RPC → MacMuleCoreService)       |  |
|  +-------------------------------------------------------+  |
|                      |  Llamadas directas                   |
|                      v                                      |
|  +-------------------------------------------------------+  |
|  |              MacMuleCore (Swift Package)                |  |
|  |  - Protocolo eD2k (TCP)              - Kad (UDP)       |  |
|  |  - CoreTransferStore                  - CoreIPFilter    |  |
|  |  - CoreUploadQueue                    - SecureIdent     |  |
|  |  - ED2KHash / ED2KLink               - UPnP / NAT-PMP  |  |
|  |  - MacMuleZlib (C bridge para zlib)  - CoreRPC         |  |
|  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
```

## Tecnologías Clave

| Componente | Tecnología |
|---|---|
| UI | SwiftUI 5 (macOS 15+), SF Symbols, NavigationSplitView |
| Comunicación inter-proceso | JSON-RPC 2.0 sobre Unix socket (AF_UNIX, SOCK_STREAM) |
| Motor de red | Network.framework, Sockets BSD (Darwin) |
| Compresión | zlib vía `MacMuleZlib` (C bridge con `-lz`) |
| Concurrencia | Swift 6 strict concurrency, async/await, actors `@MainActor` |
| Persistencia | FileManager + `Codable` en `~/Library/Application Support/MacMule/` |
| Mapeo de puertos | UPnP (`UPnPPortMapper`) y NAT-PMP (`NATPMPPortMapper`) |
| Hashes | MD4 (eD2k hash), SHA-1, SHA-256 (SecureIdent) |

## Flujo de Inicio

1. `MacMuleApp.swift` crea `MacMuleStore` (`@StateObject`)
2. `ContentView` usa `NavigationSplitView` con sidebar de secciones
3. `MacMuleStore.start()` determina conexión al daemon:
   - `MACMULE_CORE_SOCKET` env → usa socket externo
   - Sino → `MacMuleDaemonLauncher.launchBundledDaemonAsync()` lanza `macmule-core-daemon` desde `MacOS/` dentro del bundle
   - Si no hay daemon → `EmptyMacMuleCoreClient` como placeholder
4. El daemon abre un Unix socket, recibe JSON-RPC, los traduce a llamadas a `MacMuleCoreService`
5. La app sondea `snapshot` y `events(after:)` para actualizar la UI

## Referencias

- [Capa de Aplicación](02-app-layer.md)
- [Capa del Daemon](03-daemon-layer.md)
- [Paquete MacMuleCore](04-core-package.md)
