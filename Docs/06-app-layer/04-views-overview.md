# Vistas de MacMule

16 archivos de vista en `MacMule/Views/`, más `DetailViews.swift` que contiene múltiples vistas.

## DashboardView

`DetailViews.swift:310` — Vista principal tipo Home. Muestra resumen de estado: velocidades actuales, conteo de descargas activas, estado de conexión, servidor conectado, nodos Kad, y acceso rápido a acciones comunes.

## SearchTabView

`DetailViews.swift:7` como `SearchView`. Barra de búsqueda con selector Server/Kad. Resultados en tabla con columnas: nombre, tamaño, tipo, fuentes, disponibilidad, red. Botón "Download" por resultado.

## DownloadsTabView

`DetailViews.swift:712` como `DownloadsView`. Lista de descargas con filtros: **All**, **Downloading**, **Paused**, **Completed**. Cada item muestra: nombre, progreso (barra), velocidad, ETA, fuentes, tamaño. Inspector lateral con detalle de fuente, chunks, y peers activos. Ordenable por Date, Name, Progress, Speed, Size, Sources.

## UploadsTabView

`DetailViews.swift:1016` como `UploadsView`. Lista de subidas activas con slots. Muestra: nombre, velocidad de subida, cliente, progreso, posición en cola.

## SharedTabView

`DetailViews.swift:1061` como `SharedFilesView`. Carpetas compartidas y archivos. Muestra: nombre, tipo, tamaño, solicitudes recibidas, bytes subidos.

## KadView

`MacMule/Views/KadView.swift` — Panel de red Kad. Muestra: estado (running/stopped), conteo de nodos, búsquedas activas, buckets de routing table. Botones: Start/Stop, Bootstrap (host:puerto), buscar keyword, buscar fuentes por hash.

## ServersTabView

`DetailViews.swift:1126` como `NetworkView`. Lista de servidores + log panel. Cada servidor: nombre, dirección, ping, usuarios, archivos, health (Connected/Available/No response). Botones: Connect, Add Server, Remove, Import desde URL, Reset. Log panel muestra mensajes del servidor.

## StatisticsTabView

`DetailViews.swift:1676` como `StatisticsView`. Gráficas de velocidad **dual-line** (download/upload) con 60 muestras. Métricas: total descargado, total subido, ratio, duración de sesión.

## SettingsSheetView

`DetailViews.swift:1703` como `SettingsView`. Configuración completa: directorios (download/temp), límites de velocidad, nickname, puertos TCP/UDP, conexión (auto-connect, max connections, max sources), Kad (enable, bootstrap), UPnP, ofuscación, secure ident, categorías.

## LogView

`MacMule/Views/LogView.swift` — Logs del core runtime con niveles: info, warning, error. Filtro por nivel, auto-scroll.

## MessagesTabView

`MacMule/Views/MessagesTabView.swift` — Mensajes del servidor eD2k.

## CategoriesSettingsView

`MacMule/Views/CategoriesSettingsView.swift` — Gestión de categorías: añadir/eliminar con título y color.

## SourceInspectorView

`MacMule/Views/SourceInspectorView.swift` — Inspector de fuente/peer: IP, puerto, cliente, software, score, estado, cola, partes disponibles.

## StatusBarView

`MacMule/Views/StatusBarView.swift` — Barra de estado compacta para ventana principal.

## Components.swift

`MacMule/Views/Components.swift` (1011 líneas) — Componentes reutilizables: `TransferRowView`, `SpeedChartView`, `ChunkGridView`, `SectionHeaderView`, `EmptyStateView`, `ProgressBarView`, `ServerHealthBadge`, `SortableColumnHeader`, `FileKindIcon`, etc.

## DetailViews.swift

`MacMule/Views/DetailViews.swift` (1812 líneas) — Contiene 8 vistas principales: `SearchView`, `DashboardView`, `DownloadsView`, `UploadsView`, `SharedFilesView`, `NetworkView`, `StatisticsView`, `SettingsView`.

## MainWindowView

`MacMule/Views/MainWindowView.swift` (141 líneas) — Configuración de ventana principal: tamaño mínimo, toolbar, handlers de URL scheme.

## Referencias

- [Navigation](03-navigation.md) — ContentView y navegación
- [MacMuleStore](01-store.md) — datos para las vistas
- [MacMuleModels](02-models.md) — modelos usados
