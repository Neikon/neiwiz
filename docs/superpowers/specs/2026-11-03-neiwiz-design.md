# NeiWiz — diseño

## Intención

Tener un widget de Plasma 6 en la bandeja del sistema, parecido al control de
brillo del monitor, para ver y controlar las bombillas WiZ de casa sin abrir
la aplicación del móvil.

## Objetivos (v1)

- Descubrir todas las bombillas WiZ de la red local.
- Verlas en un panel desplegable desde la bandeja.
- Encender y apagar cada bombilla.
- Regular la intensidad de cada bombilla.
- Renombrar cada bombilla localmente, guardando el nombre por MAC.
- Recordar las bombillas descubiertas entre aperturas y reinicios de Plasma.
- Funcionar sin permisos de administrador y sin ningún servicio residente.

## No objetivos (v1)

- Colores, temperatura de color, escenas o efectos.
- Grupos, habitaciones o control global «todas».
- Horarios, automatizaciones, integración con la nube o con Home Assistant.
- Notificaciones o sincronización en tiempo real con cambios hechos desde el
  móvil.

## Restricciones

- Plasma 6.7.5 en Bazzite 44 (sistema inmutable).
- Python 3.14 del sistema; `uv` disponible.
- Sin daemon, sin systemd, sin autostart y sin puertos escuchando.
- Instalación completamente en el directorio del usuario.
- QML no puede usar UDP directamente; el puente con las bombillas es un
  comando Python de vida corta.
- Las bombillas y el PC deben estar en la misma red; WiZ usa UDP 38899.
- El entorno real del usuario es `192.168.1.0/24` por `eno1`.

## Arquitectura

```
Plasma (plasmashell)
└── Plasmoid QML (org.neikon.neiwiz)
    ├── CompactRepresentation: icono en la bandeja
    ├── FullRepresentation: lista, interruptores y deslizadores
    ├── ExecRunner: Plasma5Support.DataSource (engine "executable")
    ├── knownBulbs: JSON persistido en la configuración del applet
    └── nombres: ~/.config/neiwiz/bulb-names.json
             │
             │  comando puntual, termina al responder
             ▼
${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/venv/bin/python \
  ${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/wizhelper.py
    ├── discover: UDP broadcast + consulta de estado
    ├── state: getPilot a las IPs conocidas
    ├── set: setPilot (on/off/brightness)
    ├── names: leer nombres personalizados
    └── set-name: guardar o borrar un nombre
             │
             ▼
Bombillas WiZ (UDP 38899)
```

No hay proceso residente. Cada apertura del panel, cada cambio y cada
búsqueda lanzan el helper; al terminar, no queda nada ejecutándose.

## Comportamiento

### Apertura del panel

1. Si el widget no conoce bombillas, ejecuta `discover`.
2. Si las conoce, muestra inmediatamente la última lista conocida y ejecuta
   `state` para actualizarla.
3. Si todas las IPs conocidas fallan, intenta `discover` una vez de forma
   automática para recuperar cambios de IP.
4. El usuario puede forzar `discover` con el botón de buscar.

### Cambios

- Interruptor: actualización optimista; se envía `set --on` o `set --off`.
  Si falla, se revierte y se muestra el error.
- Deslizador: se actualiza visualmente mientras se arrastra y se envía al
  soltar, no en cada píxel. Si falla, se revierte.
- Una bombilla sin conexión se muestra atenuada, con los controles
  desactivados, y no bloquea al resto.

### Icono y tooltip

- Icono encendido si al menos una bombilla está encendida.
- Icono apagado en caso contrario o si aún no hay datos.
- El icono se actualiza al abrir el panel y tras los cambios propios.
- No hay sondeo periódico: los cambios externos se ven al abrir el panel.

## Interfaz

- Cabecera con «NeiWiz», botón de actualizar estado y botón de buscar.
- Lista desplazable de filas:
  - interruptor;
  - nombre (personalizado o `Bombilla F94D`, derivado de la MAC) e IP;
  - deslizador de 1 a 100 % y porcentaje;
  - botón de lápiz para cambiar el nombre, con diálogo;
  - estado «Sin conexión» cuando corresponda.
- Estados vacíos:
  - sin bombillas: explicación y botón de buscar;
  - helper no instalado: explicación y botón de reintentar;
  - error de red: mensaje y botón de reintentar.
- Textos en español.

## Datos y persistencia

La configuración del applet guarda `knownBulbs`, un JSON con `[{ip, mac}]`. Los
nombres personalizados, `{MAC: nombre}`, se guardan en
`~/.config/neiwiz/bulb-names.json`, fuera de la configuración del applet: Plasma
puede recrear la instancia del widget al reiniciar y perder esa configuración.
Los nombres son locales: no se escriben en la bombilla ni en la app WiZ. Un
nombre vacío elimina la entrada y vuelve al nombre automático. No se guarda el
estado de encendido; se consulta al abrir. Si se pierde la configuración del
applet, la siguiente apertura vuelve a descubrir, pero los nombres se conservan.

## Instalación

- `${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/venv`: entorno Python con `pywizlight`.
- `${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/wizhelper.py`: helper.
- `${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.neikon.neiwiz`: plasmoid.
- `~/.config/neiwiz/bulb-names.json`: nombres personalizados, creado al
  renombrar.
- `install.sh` es idempotente y no usa `sudo`.
- `uninstall.sh` elimina el plasmoid y el helper; conserva la configuración
  del applet.

## Riesgos y mitigaciones

- **Python 3.14 y pywizlight**: si falla, el instalador usa Python 3.13
  gestionado por `uv`.
- **Broadcast global bloqueado**: el helper reintenta con el broadcast de la
  subred local calculado desde `ip addr`.
- **IP cambiada por DHCP**: redescubrimiento automático si todas fallan,
  botón manual de búsqueda y fusión por MAC que conserva las bombillas
  conocidas que no respondan en un descubrimiento concreto.
- **Bombilla desconectada**: timeout de 2 s por bombilla; el resto sigue
  funcionando.
- **Helper ausente**: se detecta el código de salida 127 y se muestra una
  ayuda de instalación.
- **Procesos duplicados**: los botones se desactivan mientras hay una
  actualización o búsqueda en curso; los cambios por fila se bloquean
  individualmente.

## Decisiones

- Nombre visible: **NeiWiz**.
- ID: `org.neikon.neiwiz`.
- Categoría de bandeja: Hardware.
- Iconos: `flashlight-on-symbolic` / `flashlight-off-symbolic`.
- Sin control global.
- Renombrado local por MAC; no se escribe en la bombilla.
- Licencia MIT.
