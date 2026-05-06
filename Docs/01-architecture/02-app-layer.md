# Capa de Aplicación — MacMule.app

## Punto de Entrada

`MacMule/MacMuleApp.swift:4` — `MacMuleApp` es la estructura `@main` del proceso.

```swift
@main
struct MacMuleApp: App {
    @StateObject private var store = MacMuleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1020, minHeight: 660)
                .onOpenURL { url in store.handleOpenURL(url) }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("eD2k") {
                Button("Paste eD2k Link") {
                    store.pasteED2KLink()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}
```

### Responsabilidades

- Crea el `MacMuleStore` como StateObject raíz (el store vive tanto como la ventana).
- Fija el tamaño mínimo de ventana en 1020×660.
- Registra `onOpenURL` para el scheme `ed2k://`.
- Agrega el menú "eD2k" con atajo **Cmd+Shift+V** para pegar links eD2k desde el portapapeles.

## ContentView

`MacMule/ContentView.swift:14` — Vista raíz con `NavigationSplitView`.

```
+------------------------------------------------------------------+
| NavigationSplitView                                               |
| +------------+  +----------------------------------------------+ |
| | Sidebar    |  | DetailContainerView                           | |
| |            |  |                                              | |
| | Overview:  |  |  switch nav.section:                         | |
| |  Home      |  |    .dashboard  → DashboardView               | |
| |  Search    |  |    .search     → SearchView                  | |
| |            |  |    .downloads  → DownloadsView               | |
| | Transfers: |  |    .uploads    → UploadsView                 | |
| |  Downloads |  |    .shared     → SharedFilesView             | |
| |  Uploads   |  |    .kad        → KadTabView                  | |
| |  Shared    |  |    .network    → NetworkView                 | |
| |            |  |    .statistics → StatisticsView              | |
| | DHT:       |  |    .settings   → SettingsView                | |
| |  Kad       |  |    .logs       → LogView                     | |
| |            |  +----------------------------------------------+ |
| | Network:   |  Toolbar: [🔍 Search eD2k/Kad] [⚡ Connect]      |
| |  Servers   |                                                   |
| |  Statistics|  SidebarStatusFooter:                             |
| |  Settings  |   ● Connected | ↓ 1.2 MB/s | ↑ 340 KB/s          |
| |            |                                                   |
| | Diagnostics|                                                   |
| |  Logs      |                                                   |
| +------------+---------------------------------------------------+
```

### Secciones del Sidebar

Definidas en `MacMule/Models/MacMuleModels.swift:53` como `MacMuleSection`:

| Sección | Título | Icono (SF Symbol) |
|---|---|---|
| `.dashboard` | "Home" | `square.grid.2x2` |
| `.search` | "Search" | `magnifyingglass` |
| `.downloads` | "Downloads" | `arrow.down.circle` |
| `.uploads` | "Uploads" | `arrow.up.circle` |
| `.shared` | "Shared" | `folder` |
| `.kad` | "Kad" | `circle.hexagongrid` |
| `.network` | "Servers" | `server.rack` |
| `.statistics` | "Statistics" | `chart.xyaxis.line` |
| `.settings` | "Settings" | `gearshape` |
| `.logs` | "Logs" | `text.alignleft` |

Agrupadas visualmente en secciones `Overview`, `Transfers`, `DHT`, `Network`, `Diagnostics`.

### Badges contextuales

- **Downloads**: muestra contador de descargas activas (`store.activeDownloadCount`)
- **Uploads**: muestra contador de subidas activas
- **Shared**: muestra conteo de archivos compartidos

## DetailContainerView

`MacMule/ContentView.swift:296` — Mapea `MacMuleSection` a las 10 vistas detalle mediante un `switch`:

| Sección | Vista | Propósito |
|---|---|---|
| `.dashboard` | `DashboardView` | Resumen general, estado de red, próximas descargas |
| `.search` | `SearchView` | Búsqueda eD2k/Kad por palabra clave y fuente |
| `.downloads` | `DownloadsView` | Lista de descargas activas/en cola/completadas |
| `.uploads` | `UploadsView` | Lista de subidas activas |
| `.shared` | `SharedFilesView` | Archivos compartidos localmente |
| `.kad` | `KadTabView` | Estado de la red Kad, nodos, búsquedas activas |
| `.network` | `NetworkView` | Lista de servidores eD2k, conexión/conectividad |
| `.statistics` | `StatisticsView` | Gráficas de tráfico, sesión, historial |
| `.settings` | `SettingsView` | Preferencias: conexión, directorios, ancho de banda |
| `.logs` | `LogView` | Logs del core y del daemon |

## SidebarStatusFooter

`MacMule/ContentView.swift:238` — Vista anclada al fondo de la sidebar, muestra:

- **Estado de conexión**: círculo verde (conectado HighID), naranja (LowID), gris (desconectado)
- **Tráfico**: `↓ X/s` en azul, `↑ Y/s` en verde
- Si no hay tráfico muestra "No traffic"

## ToolbarSearchField

`MacMule/ContentView.swift:322` — Campo de texto en la toolbar principal:

```
Placeholder: "Search eD2k/Kad"
```
- Al presionar Enter ejecuta `store.runSearch()`
- Cambia automáticamente a la vista `Search`
- Muestra `ProgressView` mientras `store.isSearching`
- Ancho fijo de 280pt

## Manejo de URL Scheme y Atajos

### `ed2k://` URL Scheme

`MacMuleApp.swift:12-13` — `onOpenURL` delega en `store.handleOpenURL(url)`.
Cuando el usuario hace clic en un link `ed2k://` en cualquier app, macOS lo reenvía a MacMule.

### Cmd+Shift+V — Pegar link eD2k

`MacMuleApp.swift:20-22` — Comando de menú con keyboard shortcut `⌘⇧V`.
Ejecuta `store.pasteED2KLink()` que lee el portapapeles, parsea el link con `ED2KLink` y agrega la descarga.

## Referencias

- [Visión General](01-overview.md)
- [Capa del Daemon](03-daemon-layer.md)
- [Paquete MacMuleCore](04-core-package.md)
