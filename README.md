# NeiWiz

Widget de Plasma 6 para descubrir y controlar las bombillas WiZ de la red
local desde la bandeja del sistema: encender, apagar y regular la intensidad.

No usa daemon, systemd, autostart ni ningún puerto de escucha. El widget lanza
un helper Python de vida corta cuando lo necesita y, al terminar, no queda
ningún proceso residente.

## Requisitos

- Plasma 6 (probado en Plasma 6.7.5 sobre Bazzite 44).
- Python 3.11 o superior. Probado con Python 3.14.
- `uv` recomendado; si no está, el instalador usa `python3 -m venv`.
- Bombillas WiZ y el equipo en la misma red local, con UDP 38899 permitido.
- No hace falta `sudo` ni ningún permiso de administrador.

## Instalación

```bash
cd neiwiz
./install.sh
```

El instalador es idempotente. Crea un entorno en `~/.local/share/neiwiz/venv`,
instala `pywizlight`, copia el helper a `~/.local/share/neiwiz/wizhelper.py` e
instala o actualiza el plasmoid `org.neikon.neiwiz` con `kpackagetool6`.

Si `pywizlight` falla con el Python del sistema (por ejemplo, Python 3.14),
el instalador recrea el entorno con Python 3.13 gestionado por `uv` y vuelve a
intentarlo. Para actualizar NeiWiz, ejecuta `./install.sh` otra vez.

### Añadir a la bandeja

1. Clic derecho en la bandeja del sistema de Plasma.
2. Elige **Configurar la bandeja del sistema…**.
3. En **Entradas del sistema**, activa **NeiWiz**.

Si el widget no aparece en la lista, comprueba que el paquete está instalado:

```bash
kpackagetool6 --type Plasma/Applet --list | grep org.neikon.neiwiz
```

## Uso

- Al abrir el panel, NeiWiz consulta el estado de las bombillas conocidas.
- El interruptor enciende o apaga la bombilla.
- El deslizador regula la intensidad. El valor se envía al soltar, no mientras
  se arrastra.
- **Actualizar estado** vuelve a consultar todas las bombillas.
- **Buscar bombillas** fuerza un descubrimiento nuevo.
- Si una bombilla no responde, se muestra atenuada como «Sin conexión» y no
  bloquea al resto.
- Si todas las IPs conocidas fallan, se intenta un descubrimiento automático
  una vez para recuperar cambios de IP por DHCP.

El estado se consulta solo al abrir el panel o al usar los botones. Los cambios
hechos desde el móvil se ven la próxima vez que se abre el panel; no hay
sincronización en tiempo real ni sondeo periódico.

## Arquitectura

```text
Plasma (plasmashell)
└── Plasmoid QML (org.neikon.neiwiz)
    ├── Icono en la bandeja
    ├── Panel: lista, interruptores y deslizadores
    ├── ExecRunner: Plasma5Support.DataSource (engine "executable")
    └── knownBulbs: [{ip, mac}] persistido en la configuración del applet
             │
             │  comando puntual, termina al responder
             ▼
~/.local/share/neiwiz/venv/bin/python ~/.local/share/neiwiz/wizhelper.py
    ├── discover: UDP broadcast + consulta de estado
    ├── state: consulta las IPs conocidas
    └── set: on/off/intensidad
             │
             ▼
Bombillas WiZ (UDP 38899)
```

El helper devuelve siempre JSON por la salida estándar. Los errores esperados
salen como `{"ok": false, "error": "..."}` con código 0; una excepción
inesperada termina con código 1. El QML detecta el código 127 para mostrar la
ayuda de instalación cuando falta el entorno Python.

No se guarda el estado de encendido: solo la lista de bombillas conocidas
(`knownBulbs`). Si se pierde la configuración del applet, la siguiente apertura
vuelve a descubrir.

## Solución de problemas

### No aparece ninguna bombilla

- Confirma que las bombillas WiZ están encendidas y en la misma red que el PC.
- Comprueba que la red no aísla clientes (Wi-Fi de invitados, VLAN separada o
  aislamiento de clientes suelen bloquear el broadcast y el UDP 38899).
- Revisa el cortafuegos local: WiZ usa UDP 38899.
- Prueba el descubrimiento a mano:

```bash
~/.local/share/neiwiz/venv/bin/python ~/.local/share/neiwiz/wizhelper.py discover
```

El helper intenta el broadcast global y, si no funciona, el broadcast de la
subred local calculado a partir de las interfaces.

### «Falta el motor de NeiWiz»

El entorno Python o el helper no están donde el applet los espera. Ejecuta de
nuevo `./install.sh`.

### Python 3.14

`pywizlight` puede fallar con versiones muy nuevas de Python. El instalador
detecta el fallo y recrea el entorno con Python 3.13 usando `uv`. Si no tienes
`uv`, instálalo desde <https://docs.astral.sh/uv/> y vuelve a ejecutar
`./install.sh`.

### Una bombilla cambió de IP

NeiWiz guarda la MAC y redescubre automáticamente si todas las IPs conocidas
fallan. También puedes pulsar **Buscar bombillas** en el panel.

### Los cambios del móvil no aparecen al instante

Es el comportamiento previsto: no hay daemon ni sondeo en segundo plano. Abre
el panel para actualizar el estado.

### El widget no carga

```bash
bash scripts/smoke-plasmoid.sh
journalctl --user --since "10 minutes ago" | grep -i neiwiz
```

## Desarrollo

```bash
# Entorno de desarrollo
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt

# Pruebas del helper
.venv/bin/pytest -v

# Validación estática del paquete
bash scripts/check-plasmoid.sh

# Carga real del plasmoid en una ventana
bash scripts/smoke-plasmoid.sh

# Comprueba la ruta por defecto del helper (configuración limpia)
bash scripts/default-path-check.sh

# Instalación + descubrimiento real + smoke test
bash scripts/integration-check.sh
```

Archivos principales:

- `plasmoid/contents/ui/main.qml`: estado, persistencia, icono y acciones.
- `plasmoid/contents/ui/FullRepresentation.qml`: panel.
- `plasmoid/contents/ui/BulbRow.qml`: fila de bombilla.
- `plasmoid/contents/ui/ExecRunner.qml`: puente con el motor `executable`.
- `helper/wizhelper.py`: helper de descubrimiento y control.
- `tests/test_wizhelper.py`: pruebas del helper.

## Desinstalación

```bash
./uninstall.sh
```

Elimina el plasmoid y `~/.local/share/neiwiz`, pero conserva la configuración
del applet. Si quieres borrar también las bombillas recordadas, elimina el
widget de la bandeja y su grupo en
`~/.config/plasma-org.kde.plasma.desktop-appletsrc`.

## Licencia

MIT. Consulta [LICENSE](LICENSE).
