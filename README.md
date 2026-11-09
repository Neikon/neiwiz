# NeiWiz

A Plasma 6 widget for discovering and controlling WiZ bulbs on your local
network from the system tray: turn them on and off and adjust their brightness.

It uses no daemon, systemd service, autostart entry, or listening port. The
widget launches a short-lived Python helper when it needs one, and no resident
process is left behind afterwards.

## Requirements

- Plasma 6 (tested on Plasma 6.7.5 on Bazzite 45).
- Python 3.11 or newer. Tested with Python 3.14 and 3.15.
- `uv` is recommended; without it, the installer uses `python3 -m venv`.
- WiZ bulbs and the computer on the same local network, with UDP 38899 allowed.
- No `sudo` or administrator permissions required.

## Installation

```bash
cd neiwiz
./install.sh
```

The installer is idempotent. It creates an environment in
`${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/venv`, installs `pywizlight`,
copies the helper to `${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/wizhelper.py`,
and installs or updates the `org.neikon.neiwiz` plasmoid with `kpackagetool6`.

If `pywizlight` fails with the system Python (for example, with a very new
Python release), the installer recreates the environment with Python 3.13
managed by `uv` and tries again. To update NeiWiz, run `./install.sh` again.

### Adding it to the system tray

1. Right-click the Plasma system tray.
2. Choose **Configure System Tray…**.
3. Under **System Entries**, enable **NeiWiz**.

If the widget does not appear in the list, check that the package is installed:

```bash
kpackagetool6 --type Plasma/Applet --list | grep org.neikon.neiwiz
```

## Usage

- When the panel opens, NeiWiz queries the state of the known bulbs.
- The switch turns a bulb on or off.
- The slider adjusts brightness. Dragging sends the value on release;
  keyboard and mouse-wheel changes are sent immediately.
- The pencil button renames a bulb. The name is stored only in NeiWiz, keyed by
  the bulb's MAC address in
  `${XDG_CONFIG_HOME:-$HOME/.config}/neiwiz/bulb-names.json`; it is not written
  to the bulb or the WiZ app. Leave it empty to restore the automatic
  "Bulb XXXX" name.
- **Refresh state** queries every bulb again.
- **Discover bulbs** forces a new discovery. Known bulbs
  that do not respond at that moment are kept as "Offline"; they
  are not removed from the list.
- If a bulb does not respond, it is shown dimmed as "Offline" and does not
  block the others.
- If any known IP fails, NeiWiz attempts one automatic discovery to recover
  from DHCP address changes.

State is queried only when the panel opens or when you use the buttons. Changes
made from your phone appear the next time the panel opens; there is no
real-time synchronization or periodic polling.

## Architecture

```text
Plasma (plasmashell)
└── QML Plasmoid (org.neikon.neiwiz)
    ├── Tray icon
    ├── Panel: list, switches and sliders
    ├── ExecRunner: Plasma5Support.DataSource ("executable" engine)
    ├── knownBulbs: [{ip, mac}] stored in the applet configuration
    └── names: {MAC: name} in ${XDG_CONFIG_HOME:-$HOME/.config}/neiwiz/bulb-names.json
             │
             │  one-shot command, exits after replying
             ▼
${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/venv/bin/python \
  ${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/wizhelper.py
    ├── discover: UDP broadcast + state query
    ├── state: query known IPs
    ├── set: on/off/brightness
    ├── names: read custom names
    └── set-name: save or clear a name
             │
             ▼
WiZ bulbs (UDP 38899)
```

The helper always writes JSON to standard output. Expected errors are returned
as `{"ok": false, "error": "..."}` with exit code 0; an unexpected exception
exits with code 1. The QML side treats exit code 127 as a missing Python
environment and shows the installation help.

No on/off state is stored: only the list of known bulbs (`knownBulbs`, in the
applet configuration) and custom names
(`${XDG_CONFIG_HOME:-$HOME/.config}/neiwiz/bulb-names.json`, keyed by MAC).
Names live outside the applet configuration so they survive Plasma restarts,
which can recreate the widget instance.

## Troubleshooting

### No bulbs appear

- Make sure the WiZ bulbs are on and on the same network as the computer.
- Check that the network does not isolate clients (guest Wi-Fi, a separate
  VLAN, or client isolation often blocks broadcast traffic and UDP 38899).
- Check the local firewall: WiZ uses UDP 38899.
- Try discovery manually:

```bash
"${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/venv/bin/python" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz/wizhelper.py" discover
```

The helper tries the global broadcast first and, if that fails, the broadcast
address of each local interface until it finds bulbs.

### "NeiWiz engine is missing"

The Python environment or the helper is not where the applet expects it. Run
`./install.sh` again.

### Very new Python versions

`pywizlight` may fail with very new Python releases. The installer detects the
failure and recreates the environment with Python 3.13 using `uv`. If you do not
have `uv`, install it from <https://docs.astral.sh/uv/> and run `./install.sh`
again.

### A bulb changed IP address

NeiWiz stores the MAC address and rediscovers automatically if every known IP
fails. You can also press **Discover bulbs** in the panel.

### The names file is corrupt

If `${XDG_CONFIG_HOME:-$HOME/.config}/neiwiz/bulb-names.json` does not contain a
valid JSON object, renaming fails without touching the file. Back it up, delete
or repair it, then try again.

### Phone changes do not appear immediately

This is expected: there is no daemon or background polling. Open the panel to
refresh the state.

### The widget does not load

```bash
bash scripts/smoke-plasmoid.sh
journalctl --user --since "10 minutes ago" | grep -i neiwiz
```

## Development

```bash
# Development environment
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt

# Helper tests
.venv/bin/pytest -v

# Static package validation
bash scripts/check-plasmoid.sh

# QML behavior tests (requires python3-pyside6)
bash scripts/qml-test.sh

# Load the plasmoid in a real window
bash scripts/smoke-plasmoid.sh

# Check the default helper path (clean configuration)
bash scripts/default-path-check.sh

# Check that discovery preserves known bulbs
bash scripts/discover-merge-check.sh

# Installation + real discovery + smoke test
bash scripts/integration-check.sh
```

Main files:

- `plasmoid/contents/ui/main.qml`: state, persistence, icon and actions.
- `plasmoid/contents/ui/FullRepresentation.qml`: panel.
- `plasmoid/contents/ui/BulbRow.qml`: bulb row.
- `plasmoid/contents/ui/ExecRunner.qml`: bridge to the `executable` engine.
- `helper/wizhelper.py`: discovery and control helper.
- `tests/test_wizhelper.py`: helper tests.

## Uninstallation

```bash
./uninstall.sh
```

This removes the plasmoid and `${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz`, but
preserves the applet configuration and the names in
`${XDG_CONFIG_HOME:-$HOME/.config}/neiwiz/bulb-names.json`. To also delete the
remembered bulbs, remove the widget from the system tray and its group from
`~/.config/plasma-org.kde.plasma.desktop-appletsrc`; to delete the names, remove
`${XDG_CONFIG_HOME:-$HOME/.config}/neiwiz/bulb-names.json`.

## License

MIT. See [LICENSE](LICENSE).
