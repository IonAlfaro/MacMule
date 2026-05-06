# Documentación de MacMule

MacMule es un cliente nativo eD2k/eMule para macOS construido con SwiftUI, respaldado por un paquete Swift `MacMuleCore` independiente y un proceso daemon local.

## Índice

### Arquitectura general
- [Visión general](01-architecture/01-overview.md) — Qué es MacMule, las 3 capas, stack tecnológico
- [Capa de aplicación](01-architecture/02-app-layer.md) — SwiftUI, NavigationSplitView, vistas
- [Capa del daemon](01-architecture/03-daemon-layer.md) — macmule-core-daemon, JSON-RPC, CoreSocketServer
- [Paquete Core](01-architecture/04-core-package.md) — MacMuleCore, 43 módulos, package structure

### Protocolos de red
- [Visión general de eD2k](02-protocols/01-ed2k-overview.md) — La red eD2k, servidores, peers, Kad
- [Paquetes TCP eD2k](02-protocols/02-ed2k-tcp-packets.md) — Formato de paquetes, opcodes, tags
- [Sesiones con servidor](02-protocols/03-server-session.md) — Login, búsqueda, fuentes, eventos
- [Sesiones peer-to-peer](02-protocols/04-peer-session.md) — Handshake, descarga de partes, source exchange
- [Listener de peers](02-protocols/05-peer-listener.md) — Conexiones entrantes, LowID
- [Kademlia DHT (Kad)](02-protocols/06-kad-dht.md) — Red distribuida, Kademlia, búsquedas

### Servicios Core
- [MacMuleCoreService](03-core-services/01-core-service.md) — Orquestador central, failover, source discovery
- [CoreTransferStore](03-core-services/02-transfer-store.md) — Persistencia .part, chunks, hash verification
- [CoreUploadQueue](03-core-services/03-upload-queue.md) — Slots de subida, cola de espera, scoring
- [CoreSharedFileList](03-core-services/04-shared-files.md) — Archivos compartidos, escaneo, hashing
- [CoreScheduler](03-core-services/05-scheduler.md) — Automatización por tiempo
- [CoreWebServer](03-core-services/06-web-server.md) — Interfaz web embebida

### Seguridad
- [IP Filter](04-security/01-ip-filter.md) — Filtro de rangos IP
- [Secure Ident](04-security/02-secure-ident.md) — Identidad Curve25519
- [Obfuscation Layer](04-security/03-obfuscation.md) — Ofuscación de protocolo
- [Creditos](04-security/04-credits.md) — Sistema de créditos

### Kad (Kademlia DHT)
- [Visión general](05-kad/01-overview.md) — Arquitectura Kad en MacMule
- [Routing Table](05-kad/02-routing-table.md) — KadRoutingTable, buckets, contactos
- [Search Manager](05-kad/03-search-manager.md) — Búsquedas de keywords y fuentes
- [UDP Listener](05-kad/04-udp-listener.md) — Escucha y envío UDP

### Capa de aplicación
- [MacMuleStore](06-app-layer/01-store.md) — Estado global, settings, core client
- [Modelos](06-app-layer/02-models.md) — MacMuleModels, TransferItem, secciones
- [Navegación](06-app-layer/03-navigation.md) — ContentView, sidebar, transiciones
- [Vistas](06-app-layer/04-views-overview.md) — Las 16 vistas de la interfaz
- [Cliente del daemon](06-app-layer/05-daemon-client.md) — DaemonMacMuleCoreClient, launcher
- [Enlaces eD2k](06-app-layer/06-ed2k-links.md) — Formato ed2k://, URL scheme

### Flujo de datos
- [App → Daemon](07-data-flow/01-app-to-daemon.md) — JSON-RPC, métodos, CoreRPCHandler
- [Daemon → Red](07-data-flow/02-daemon-to-network.md) — Network.framework, TCP, UDP
- [Descarga peer-to-peer](07-data-flow/03-peer-download-flow.md) — Flujo completo: link → archivo
- [Persistencia](07-data-flow/04-persistence.md) — Sidecars, .part, nodes.dat, checkpoint

### Networking
- [UPnP](08-networking/01-upnp.md) — Mapeo automático de puertos via UPnP
- [NAT-PMP](08-networking/02-nat-pmp.md) — Mapeo via NAT-PMP

### Desarrollo
- [Compilación y release](09-development/01-building.md) — Cómo compilar, testear, generar release
- [Estructura del proyecto](09-development/02-project-structure.md) — Árbol de directorios
- [Solución de problemas](09-development/03-troubleshooting.md) — Problemas comunes y soluciones
