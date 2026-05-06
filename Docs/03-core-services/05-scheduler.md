# CoreScheduler — Automatización por Tiempo

**Archivo fuente:** `MacMuleCore/Sources/MacMuleCore/CoreScheduler.swift` — 199 líneas

**Propósito:** `CoreScheduler` implementa un sistema de automatización basado en tiempo, similar al scheduler de eMule. Permite definir acciones que se ejecutan automáticamente en días y horas específicos.

---

## ScheduleEntry

`CoreScheduler.swift:37-95`

Cada entrada programada define:

```swift
public struct ScheduleEntry: Identifiable {
    public var id: UUID
    public var title: String
    public var days: Set<Int>          // 0=Dom, 1=Lun, ..., 6=Sab
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var enabled: Bool
    public var actions: [ScheduleAction]
}
```

### dayNames / formattedTime

- `dayNames: [String]` — convierte `days` a nombres ("Mon", "Tue", etc.)
- `formattedTime: String` — formato "23:00 - 07:00"

### isActive

`CoreScheduler.swift:79-94`

```swift
public func isActive(at date: Date = Date()) -> Bool
```

Evalúa si la entrada está activa en una fecha/hora dada:

1. Verifica `enabled` y `days` no vacío
2. Verifica que el día de la semana coincida
3. Compara minutos desde medianoche contra ventana `start-end`
4. Soporta ventanas que cruzan la medianoche (start > end)

---

## ScheduleActionType

`CoreScheduler.swift:3-25`

Ocho tipos de acciones disponibles:

| Tipo | rawValue | default value |
|------|----------|---------------|
| `setUploadLimit` | "Limit upload" | "100" |
| `setDownloadLimit` | "Limit download" | "500" |
| `pauseCategory` | "Pause category" | "" |
| `resumeCategory` | "Resume category" | "" |
| `limitSources` | "Limit sources" | "10" |
| `setMaxConnections` | "Max connections" | "100" |
| `disconnect` | "Disconnect" | "" |
| `connect` | "Connect" | "" |

---

## Timer

`CoreScheduler.swift:154-163`

```swift
public func start() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .seconds(60))
    timer.setEventHandler { [weak self] in self?.checkAndApply() }
    timer.resume()
    self.timer = timer
    checkAndApply()
}
```

- Timer cada **60 segundos**
- Usa `DispatchSourceTimer` en cola `com.macmule.scheduler` con QoS `.utility`
- Se inicia automáticamente en `MacMuleCoreService.init` si `scheduler.enabled == true`
- `stop()` cancela el timer y limpia `lastActiveActionIDs`

---

## Activación / Desactivación de Acciones

`CoreScheduler.swift:171-189`

```swift
private func checkAndApply() {
    var activeIDs = Set<UUID>()
    for entry in entries where entry.isActive() {
        activeIDs.insert(entry.id)
        if !lastActiveActionIDs.contains(entry.id) {
            log("Scheduler: entry '\(entry.title)' activated")
            for action in entry.actions { actionHandler(action) }
        }
    }
    for id in lastActiveActionIDs.subtracting(activeIDs) {
        if let entry = entries.first(where: { $0.id == id }) {
            log("Scheduler: entry '\(entry.title)' deactivated")
        }
    }
    lastActiveActionIDs = activeIDs
}
```

- Solo ejecuta `actionHandler` cuando una entrada **entra** en su ventana activa
- Cuando **sale** de la ventana, solo loggea (las acciones de "desactivación" dependen del tipo)
- El actionHandler se conecta a `MacMuleCoreService.handleSchedulerAction` (`CoreService.swift:702-723`)

---

## Persistencia

`CoreScheduler.swift:117-128`

```swift
public func load() throws   // Carga desde scheduler.json
public func save() throws   // Guarda a scheduler.json con .atomic
```

Archivo: `{rootDirectory}/scheduler.json`

```json
{
    "enabled": true,
    "entries": [
        {
            "id": "...",
            "title": "Night mode",
            "days": [1,2,3,4,5],
            "startHour": 23,
            "startMinute": 0,
            "endHour": 7,
            "endMinute": 0,
            "enabled": true,
            "actions": [
                { "type": "Limit upload", "value": "50" },
                { "type": "Limit download", "value": "200" }
            ]
        }
    ]
}
```

---

## Manejo de Acciones

`CoreService.swift:702-723`

El `actionHandler` del scheduler se conecta a `MacMuleCoreService.handleSchedulerAction`:

```swift
switch action.type {
case .setUploadLimit:   maxUploadBytesPerSecond = value * 1024
case .setDownloadLimit: maxDownloadBytesPerSecond = value * 1024
case .disconnect:       disconnectServer()
case .connect:          reconnectConfiguration.map { _ = connectToServer($0) }
default:                log only
}
```

---

## Referencias

- [MacMuleCoreService](01-core-service.md) — orquestador que maneja las acciones del scheduler
- [Vision General de MacMule](../01-architecture/01-overview.md) — arquitectura general
