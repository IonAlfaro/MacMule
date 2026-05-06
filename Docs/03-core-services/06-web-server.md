# CoreWebServer — Interfaz Web Embebida

**Archivo fuente:** `MacMuleCore/Sources/MacMuleCore/CoreWebServer.swift` — 310 líneas

**Proposito:** `CoreWebServer` implementa un servidor HTTP embebido en el core que permite monitorear y controlar MacMule desde un navegador web, sin necesidad de la aplicacion SwiftUI.

---

## Inicializacion

`CoreWebServer.swift:16-24`

```swift
public init(
    serviceProvider: @escaping () -> CoreSnapshot,
    commandHandler: @escaping (String, [String: String]) -> CoreSnapshot?,
    logHandler: (@Sendable (String) -> Void)? = nil
)
```

- `serviceProvider` — clausura que retorna el `CoreSnapshot` actual
- `commandHandler` — clausura que recibe comandos (connect, disconnect, search, etc.)
- `logHandler` — handler para logs

Se construye en `MacMuleCoreService.webStart(port:password:)` (`CoreService.swift:635-659`).

---

## Inicio y Detencion

### start

`CoreWebServer.swift:26-47`

```swift
public func start(port: UInt16, password: String = "") throws
```

1. Crea `NWListener` en el puerto especificado via Network.framework
2. Configura `stateUpdateHandler` para detectar cuando el listener esta listo
3. Configura `newConnectionHandler` para procesar peticiones HTTP entrantes
4. Arranca en la cola `com.macmule.web` con QoS `.utility`

### stop

`CoreWebServer.swift:49-56`

Cancela el listener y resetea el estado.

---

## Endpoints HTTP

| Ruta | Metodo | Descripcion |
|------|--------|-------------|
| `/` | GET | HTML dashboard con CSS dark theme |
| `/status` | GET | JSON con el snapshot completo del core |
| `/connect` | GET | Conecta al servidor (con params opcionales) |
| `/disconnect` | GET | Desconecta del servidor |
| `/search` | GET | Busca en la red eD2k (`?q=...`) |
| `/add_link` | GET | Agrega un link eD2k (`?link=ed2k://...`) |

---

## HTML Dashboard

`CoreWebServer.swift:187-287`

`generateHTML(snapshot:)` genera una pagina HTML completa con:

### CSS (Dark Theme)

- Fondo `#1a1a2e`, tarjetas `#16213e`, badges `#00d4aa` / `#e94560`
- Estilo moderno con `grid-template-columns`, border-radius, flexbox
- Diseño responsive via `auto-fit`

### Stats

```html
<div class="stat">
  <div class="label">Status</div>
  <div class="value">Connected / Disconnected</div>
</div>
<div class="stat">
  <div class="label">Active downloads</div>
  <div class="value">{count}</div>
</div>
<div class="stat">
  <div class="label">Downloaded</div>
  <div class="value">{bytes}</div>
</div>
<div class="stat">
  <div class="label">Kad Nodes</div>
  <div class="value">{count}</div>
</div>
```

### Tabla de Descargas Activas

Muestra: Nombre, Tamano, Progreso (porcentaje), Velocidad, Estado (badge coloreado).

### Tabla de Servidores

Muestra: Nombre, Direccion, Usuarios, Ping.

### Quick Actions

- Botones Connect / Disconnect
- Formulario de busqueda
- Formulario para agregar links eD2k

---

## JSON Status

`CoreWebServer.swift:122-125`

```swift
case "/status":
    let snapshot = serviceProvider()
    let json = encodeJSON(snapshot: snapshot)
    sendResponse(connection, status: 200, body: json, contentType: "application/json")
```

Retorna el `CoreSnapshot` completo serializado como JSON.

---

## Autenticacion Opcional

`CoreWebServer.swift:13, 26, 32-33`

```swift
private var password: String = ""
private var isAuthenticated = false
```

Se puede pasar un `password` al iniciar el servidor via `webStart(port:password:)`. Actualmente la autenticacion esta declarada pero **no implementada** en el procesamiento de requests (TODO: verificar header Authorization).

---

## Procesamiento de Requests

`CoreWebServer.swift:69-150`

1. Recibe datos raw de la conexion TCP
2. Parsea la request HTTP (primera linea, headers, body)
3. Extrae metodo (GET/POST), path y query params
4. Soporta tanto GET (query string) como POST (body url-encoded)
5. Delega a los handlers correspondientes
6. Envia respuestas HTTP/1.1 con `Connection: close`

### Redirecciones

Los endpoints `/connect`, `/disconnect`, `/search`, `/add_link` responden con HTTP 302 redirect a `/`.

---

## Referencias

- [MacMuleCoreService](01-core-service.md) — orquestador que inicia/detiene el web server
- [Vision General de MacMule](../01-architecture/01-overview.md) — arquitectura general
