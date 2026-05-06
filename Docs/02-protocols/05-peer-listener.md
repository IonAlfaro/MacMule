# Listener TCP para Conexiones Entrantes de Peers

## Propósito

El listener TCP (`ED2KPeerTCPListener`) permite que otros clientes eD2k se conecten a MacMule para solicitar partes de archivos que estamos compartiendo. Escucha en un puerto TCP configurable (default 4662).

## Importancia para HighID/LowID

Si el listener falla al iniciar (puerto ocupado, firewall bloqueando), la conexión se considera **LowID** — el cliente no es accesible directamente desde internet y depende del servidor para callbacks.

```
┌──────────────────┐     ┌──────────────────┐
│  Peer externo    │────►│  MacMule         │
│  (solicita parte)│     │  Listener:4662   │
└──────────────────┘     └──────────────────┘
                               │
                          ┌────▼────┐
                          │ Incoming│
                          │ Peer    │
                          │ Session │
                          └─────────┘
```

## ED2KPeerTCPListener

Archivo: `ED2KPeerTCPListener.swift`

### Estados

```swift
public enum ED2KPeerTCPListenerState {
    case starting(UInt16)    // Inicializando en puerto X
    case listening(UInt16)   // Escuchando activamente
    case failed(String)      // Error (puerto ocupado, permisos)
    case cancelled           // Cancelado por el usuario
}
```

### Diagrama de estados

```
       ┌──────────┐
       │   init   │
       └────┬─────┘
            │ start()
            ▼
      ┌───────────┐
      │ starting  │
      │ (puerto)  │
      └─────┬─────┘
            │ NWListener .ready
            ▼
       ┌──────────┐
       │ listening│ ← esperando conexiones
       └────┬─────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌──────────┐ ┌────────┐
│ cancelled│ │ failed │
└──────────┘ └────────┘
```

### Eventos

```swift
public enum ED2KPeerTCPListenerEvent {
    case stateChanged(ED2KPeerTCPListenerState)
    case accepted(ED2KPeerEndpoint)                           // nuevo peer conectado
    case sessionEvent(ED2KPeerEndpoint, ED2KPeerSessionEvent) // evento de sesión
    case helloAnswerSent(ED2KPeerEndpoint)                    // helloAnswer enviado
    case helloAnswerFailed(endpoint: ED2KPeerEndpoint, message: String)
    case receiveFailed(endpoint: ED2KPeerEndpoint, message: String)
}
```

### Configuración

El listener se instancia con la misma configuración que las sesiones salientes:

```swift
public struct ED2KPeerSessionConfiguration {
    public var userHash: Data
    public var clientID: UInt32
    public var tcpPort: UInt16       // puerto donde escuchar
    public var nickname: String
    public var version: String
    public var serverEndpoint: ED2KServerEndpoint
}
```

## Transporte Intercambiable

`ED2KPeerTCPListenerTransport` abstrae el listener subyacente:

```swift
public protocol ED2KPeerTCPListenerTransport: AnyObject {
    var stateUpdateHandler: ((ED2KPeerTCPListenerTransportState) -> Void)? { get set }
    var connectionHandler: ((ED2KAcceptedPeerConnection) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}
```

**Implementación real**: `NetworkED2KPeerTCPListenerTransport` — usa `NWListener`

```swift
public final class NetworkED2KPeerTCPListenerTransport: ED2KPeerTCPListenerTransport {
    private let listener: NWListener?

    public init(port: UInt16, parameters: NWParameters = .tcp) {
        // NWListener(using: .tcp, on: NWEndpoint.Port(port))
    }
}
```

**Noop para tests**: `NoopED2KPeerTCPListenerTransport` (no hace nada, siempre cancela).

## Manejo de Conexiones Entrantes

Cuando un peer externo se conecta:

```
Peer externo                    MacMule (Listener)
   │                                   │
   │──── TCP connect ────────────────► │
   │                                   ├── .accepted(endpoint)
   │                                   ├── transport.start(queue)
   │                                   │
   │──── hello (0x01) ───────────────► │
   │                                   ├── session.receive(data)
   │                                   ├── .sessionEvent(.peerHello)
   │                                   ├── sendHelloAnswer()
   │                                   │
   │◄─── helloAnswer (0x4C) ──────────│
   │                                   ├── .helloAnswerSent
   │                                   │
   │──── requestParts (0x47) ────────► │
   │                                   ├── .sessionEvent(.partRequest)
   │                                   │
   │──── ... más paquetes ───────────► │
   │                                   │
   │──── (peer cierra conexión) ──────►│
   │                                   └── onFinished()
```

### IncomingPeerConnection

Cada conexión entrante se maneja mediante una instancia privada de `IncomingPeerConnection`:

```swift
private final class IncomingPeerConnection {
    private let endpoint: ED2KPeerEndpoint
    private var session: ED2KPeerSession
    private let transport: ED2KPeerTCPTransport
    private let eventHandler: (ED2KPeerTCPListenerEvent) -> Void
    private let onFinished: () -> Void
}
```

1. Al recibir `hello`, automáticamente envía `helloAnswer`
2. Los eventos de sesión se reenvían al `eventHandler` del listener
3. Al terminar (error o cierre), se notifica `onFinished` para limpieza

## NWListener State Handling

El listener `NetworkED2KPeerTCPListenerTransport` traduce estados de `NWListener`:

```swift
private func handleState(_ state: NWListener.State) {
    switch state {
    case .ready:
        stateUpdateHandler?(.ready(port))       // listener activo
    case .failed(let error):
        stateUpdateHandler?(.failed(error))     // error (puerto en uso, etc.)
    case .cancelled:
        stateUpdateHandler?(.cancelled)         // cancelado manualmente
    default: break                              // .setup, .waiting
    }
}
```

## Flujo de Inicio

```
┌─────────────────────────────────────────────────────┐
│ 1. ED2KPeerTCPListener(configuration:).start()      │
│    ├─ stateChanged(.starting(config.tcpPort))        │
│    └─ transport.stateUpdateHandler = handleState      │
│       transport.connectionHandler = handleConnection  │
│       transport.start(queue:)                         │
│                                                       │
│ 2. NetworkED2KPeerTCPListenerTransport.start(queue:)  │
│    └─ NWListener.start(queue:)                        │
│                                                       │
│ 3. NWListener.state → .ready                          │
│    └─ stateChanged(.listening(port))                   │
│                                                       │
│ 4. NWListener.newConnectionHandler (por cada peer)    │
│    ├─ AcceptedNetworkED2KPeerTCPTransport(connection)  │
│    └─ connectionHandler(acceptedConnection)            │
│                                                       │
│ 5. ED2KPeerTCPListener.handleAcceptedConnection()     │
│    ├─ IncomingPeerConnection creado y guardado         │
│    ├─ emit(.accepted(endpoint))                        │
│    └─ connection.start(queue:)                         │
│                                                       │
│ 6. ED2KPeerTCPListener.cancel()                       │
│    ├─ cancelar todas las IncomingPeerConnection        │
│    └─ transport.cancel() → stateChanged(.cancelled)    │
└─────────────────────────────────────────────────────┘
```

## Enlaces

- [01: Visión General de eD2k](01-ed2k-overview.md)
- [02: Paquetes eD2k TCP](02-ed2k-tcp-packets.md)
- [04: Sesiones Peer-to-Peer](04-peer-session.md)
- `ED2KPeerTCPListener.swift` — Implementación completa
