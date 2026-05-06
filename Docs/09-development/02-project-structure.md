# Estructura del Proyecto MacMule

```
MacMule/                          ← Aplicación SwiftUI (macOS 15+)
├── MacMuleApp.swift              Entry point, @main
├── ContentView.swift             NavigationSplitView + Sidebar
├── MacMule.entitlements          Sandbox + permisos
├── Info.plist                    Bundle config, URL schemes
│
├── Models/
│   ├── MacMuleStore.swift        Store central ObservableObject (811 lines)
│   └── MacMuleModels.swift       Modelos de UI (455 lines)
│
├── Views/
│   ├── DetailViews.swift         Dashboard, Search, Downloads, Uploads,
│   │                             Shared, Network, Stats, Settings (1812 lines)
│   ├── Components.swift          Componentes reutilizables (1011 lines)
│   ├── KadView.swift             Panel Kad
│   ├── LogView.swift             Visor de logs
│   ├── MessagesTabView.swift     Mensajes del servidor
│   ├── CategoriesSettingsView.swift Categorías
│   ├── SourceInspectorView.swift Inspector de fuentes
│   ├── StatusBarView.swift       Barra de estado
│   └── MainWindowView.swift      Configuración de ventana
│
├── Core/
│   ├── DaemonMacMuleCoreClient.swift  Cliente Unix socket (680 lines)
│   ├── MacMuleCoreClient.swift       Protocolo cliente core
│   ├── MacMuleDaemonLauncher.swift    Lanzador del daemon
│   └── ServerMetParser.swift          Parser server.met
│
└── Resources/
    ├── Assets.xcassets/
    └── CoreDefaultED2KServers.swift   Servidores bundled

MacMuleCore/                      ← Swift Package (motor de red)
├── Package.swift
├── Sources/MacMuleCore/
│   ├── Protocolos eD2k/
│   │   ├── ED2KProtocol.swift         Opcodes, tipos de paquete
│   │   ├── ED2KServerSession.swift    Sesión con servidor
│   │   ├── ED2KServerTCPConnection.swift Conexión TCP a servidor
│   │   ├── ED2KPeerSession.swift      Sesión peer-to-peer
│   │   ├── ED2KPeerTCPConnection.swift Conexión TCP a peer
│   │   ├── ED2KPeerTCPListener.swift  Listener TCP para peers
│   │   └── ED2KLink.swift             Parseo de enlaces ed2k
│   │
│   ├── Kad/
│   │   ├── KadService.swift           Orquestador Kad
│   │   ├── KadRoutingTable.swift      Tabla Kademlia (182 lines)
│   │   ├── KadRoutingBin.swift        Bucket individual (78 lines)
│   │   ├── KadSearchManager.swift     Gestor de búsquedas (168 lines)
│   │   ├── KadLookupCoordinator.swift Coordinador lookup (118 lines)
│   │   ├── KadUDPListener.swift       Listener UDP (152 lines)
│   │   ├── KadPacketHandler.swift     Manejador de paquetes
│   │   ├── KadContact.swift           Contacto/nodo
│   │   ├── KadPrefsStore.swift        Preferencias Kad
│   │   ├── KadUInt128.swift           Entero 128 bits
│   │   └── KadClientSearcher.swift    Envío de peticiones
│   │
│   ├── CoreServices/
│   │   ├── CoreService.swift          Servicio principal del daemon
│   │   ├── CoreSocketServer.swift     Listener Unix socket
│   │   ├── CoreRPCHandler.swift       Traductor JSON-RPC
│   │   ├── CoreTransferStore.swift    Almacén de transferencias
│   │   ├── CoreUploadQueue.swift      Cola de subidas
│   │   └── CoreRarityScheduler.swift  Planificador de rareza
│   │
│   ├── Security/
│   │   ├── CoreIPFilter.swift         Filtro de IP (95 lines)
│   │   ├── CoreSecureIdent.swift      Identidad Curve25519 (40 lines)
│   │   ├── CoreObfuscationLayer.swift Ofuscación RC4 (146 lines)
│   │   └── CoreCreditsList.swift      Sistema de créditos (125 lines)
│   │
│   ├── Networking/
│   │   ├── UPnPPortMapper.swift       UPnP IGD (564 lines)
│   │   └── NATPMPPortMapper.swift     NAT-PMP (404 lines)
│   │
│   └── Utils/
│       ├── MacMuleZlib.swift          Bridge C para zlib
│       ├── CoreDefaultED2KServers.swift Lista bundled de servidores
│       └── ...
│
└── Tests/MacMuleCoreTests/
    ├── ED2KLinkTests.swift
    ├── UPnPPortMapperTests.swift
    ├── NATPMPPortMapperTests.swift
    └── ...

Docs/                             ← Documentación técnica (español)
├── 01-architecture/              Arquitectura general
├── 02-protocols/                 Protocolos eD2k
├── 03-core-services/             Servicios del core
├── 04-security/                  Seguridad
├── 05-kad/                       Red Kad
├── 06-app-layer/                 Capa de aplicación
├── 07-data-flow/                 Flujo de datos
├── 08-networking/                Mapeo de puertos
└── 09-development/               Desarrollo y compilación
```

## Referencias

- [Building](01-building.md) — compilación y tests
- [Troubleshooting](03-troubleshooting.md) — problemas comunes
