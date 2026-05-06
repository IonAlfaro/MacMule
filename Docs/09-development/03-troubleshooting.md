# Troubleshooting — Problemas Comunes

## Puertos Ocupados

**Síntoma**: El daemon no inicia, log muestra "Address already in use".

**Solución**:
```bash
# Verificar qué proceso ocupa el puerto
sudo lsof -i :4662
sudo lsof -i :4672

# Matar el proceso
sudo kill -9 <PID>
```

O cambiar puertos en Settings > TCP Port / UDP Port.

## LowID

**Síntoma**: Conectado al servidor pero muestra "LowID". El servidor reporta ID bajo.

**Causas**:
- Puerto TCP (4662) no está abierto/reenviado al firewall
- NAT sin UPnP/NAT-PMP
- ISP bloquea tráfico entrante

**Soluciones**:
1. Abrir puerto TCP 4662 en el router (forwarding)
2. Habilitar UPnP en Settings
3. Verificar firewall de macOS: System Settings > Network > Firewall
4. Usar un VPN que permita port forwarding

## Firewall de macOS

**Síntoma**: Los peers no pueden conectarse a MacMule.

**Solución**:

```bash
# Agregar MacMule al firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --add /Applications/MacMule.app

# O desactivar firewall temporalmente
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
```

O desde System Settings > Network > Firewall > Options > Add MacMule.app.

## UPnP Falló

**Síntoma**: Log muestra "No se encontro un router UPnP/IGD en la red local."

**Causas**:
- Router no soporta UPnP
- UPnP desactivado en el router
- Múltiples routers/NAT en cascada

**Soluciones**:
1. Verificar UPnP en panel de administración del router
2. NAT-PMP como alternativa (automático si ambos están habilitados)
3. Port forwarding manual en el router

## Kad no se conecta

**Síntoma**: Kad muestra "Stopped" o nodo count = 0.

**Soluciones**:
1. Verificar puerto UDP 4672 abierto
2. Bootstrap manual: Settings > Kad > añadir un nodo conocido
3. Verificar `nodes.dat` existe en `~/Library/Application Support/MacMule/Core/`
4. Esperar unos minutos tras conexión a servidor (Kad obtiene nodos vía servidor)

## El daemon no arranca

**Síntoma**: "Could not connect to daemon" o runtimeStatus warning.

**Soluciones**:

```bash
# Verificar si el binario existe
ls /Applications/MacMule.app/Contents/MacOS/macmule-core-daemon

# Verificar socket
# Forzar variable de entorno para debug
MACMULE_CORE_SOCKET=/tmp/macmule-core.sock /Applications/MacMule.app/Contents/MacOS/MacMule

# Correr daemon directamente
/Applications/MacMule.app/Contents/MacOS/macmule-core-daemon \
  --socket /tmp/macmule-test.sock \
  --storage ~/Library/Application\ Support/MacMule/Core/
```

## Corrupción de .part files

**Síntoma**: Error de verificación de hash en chunks descargados.

**Solución**: El sistema de resume checkpoint maneja esto automáticamente. Si persiste:

```bash
# Eliminar .part file y reiniciar descarga
rm ~/Library/Application\ Support/MacMule/Core/Temp/<hash>.part
```

## Logs

Los logs del core se muestran en la vista Logs de la app. También hay logs del sistema:

```bash
log stream --predicate 'subsystem == "com.macmule.core"'
```

## Referencias

- [Building](01-building.md) — compilación
- [Project Structure](02-project-structure.md) — estructura
