# ContentView — Navegación Principal

`MacMule/ContentView.swift` (409 líneas)

## Arquitectura

```swift
struct ContentView: View {
    @EnvironmentObject private var store: MacMuleStore
    // ...
    var body: some View {
        NavigationSplitView {
            SidebarNavList(nav: nav)
                .safeAreaInset(edge: .top) { SidebarBrandHeader() }
                .safeAreaInset(edge: .bottom) { SidebarStatusFooter() }
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            DetailContainerView(nav: nav)
        }
        .frame(minWidth: 1020, minHeight: 660)
    }
}
```

## Sidebar — Secciones agrupadas

### Overview
- Home (Dashboard)
- Search

### Transfers
- Downloads
- Uploads
- Shared

### DHT
- Kad

### Network
- Servers
- Statistics
- Settings

### Diagnostics
- Logs

## SidebarBrandHeader

Muestra el logo "MacMule", estado de conexión (online/offline), y chips de velocidad (download/upload).

## SidebarStatusFooter

Muestra estado de conexión con indicador de color:

- **Verde**: conectado
- **Naranja**: LowID
- **Gris**: desconectado

Más velocidades de transferencia si hay actividad.

## DetailContainerView

```swift
private struct DetailContainerView: View {
    var body: some View {
        Group {
            switch nav.section ?? .dashboard {
            case .dashboard:   DashboardView()
            case .search:      SearchView()
            case .downloads:   DownloadsView()
            case .uploads:     UploadsView()
            case .shared:      SharedFilesView()
            case .kad:         KadTabView()
            case .network:     NetworkView()
            case .statistics:  StatisticsView()
            case .settings:    SettingsView()
            case .logs:        LogView()
            }
        }
        .transition(.opacity)
    }
}
```

## Toolbar

```swift
.toolbar(id: "main") {
    ToolbarItem(id: "quickSearch") { ToolbarSearchField() }
    ToolbarItem(id: "connectToggle") { Button("Connect/Disconnect") }
}
```

- Barra de búsqueda rápida (280px)
- Botón Connect/Disconnect con icono de rayo

## Sidebar Badges

- Downloads: badge con conteo de descargas activas
- Uploads: badge si hay subidas activas
- Shared: badge si hay archivos compartidos

## Referencias

- [MacMuleStore](01-store.md) — store central
- [MacMuleModels](02-models.md) — tipos de sección
- [Views Overview](04-views-overview.md) — vistas detalle
