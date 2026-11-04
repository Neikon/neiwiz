#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_DATA="$TMP_HOME/xdg-data"
LOG="$(mktemp)"
MARKER="$TMP_HOME/helper-calls"
CONFIG="$TMP_HOME/.config/plasmawindowedrc"
PID=""

cleanup() {
    if [[ -n "$PID" ]]; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_HOME" "$LOG"
}
trap cleanup EXIT

mkdir -p "$TMP_DATA/neiwiz/venv/bin" "$TMP_HOME/.config" "$TMP_HOME/.cache"
ln -s "$(command -v python3)" "$TMP_DATA/neiwiz/venv/bin/python"

if ! XDG_DATA_HOME="$TMP_DATA" kpackagetool6 --type Plasma/Applet \
    --upgrade "$ROOT/plasmoid" >/dev/null 2>&1; then
    XDG_DATA_HOME="$TMP_DATA" kpackagetool6 --type Plasma/Applet \
        --install "$ROOT/plasmoid" >/dev/null
fi

cat > "$TMP_DATA/neiwiz/wizhelper.py" <<'PY'
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["NEIWIZ_TEST_MARKER"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")

command = args[0] if args else ""
if command == "state":
    print(json.dumps({"ok": True, "bulbs": [{
        "ip": "192.168.1.149",
        "online": False,
        "on": False,
        "brightness": 100,
        "mac": "444f8e318dc4",
    }]}))
elif command == "discover":
    print(json.dumps({"ok": True, "bulbs": [{
        "ip": "192.168.1.205",
        "online": True,
        "on": False,
        "brightness": 100,
        "mac": "444f8e3c2ed4",
    }]}))
else:
    print(json.dumps({"ok": True}))
PY

cat > "$CONFIG" <<'INI'
[Applets][4]
immutability=1
plugin=org.neikon.neiwiz

[Applets][4][Configuration][General]
knownBulbs=[{"ip":"192.168.1.149","mac":"444f8e318dc4"}]
INI

HOME="$TMP_HOME" \
XDG_CONFIG_HOME="$TMP_HOME/.config" \
XDG_CACHE_HOME="$TMP_HOME/.cache" \
XDG_DATA_HOME="$TMP_DATA" \
NEIWIZ_TEST_MARKER="$MARKER" \
QT_FORCE_STDERR_LOGGING=1 \
plasmawindowed org.neikon.neiwiz >"$LOG" 2>&1 &
PID=$!

known=""
for _ in $(seq 1 40); do
    if [[ -f "$CONFIG" ]]; then
        known="$(python3 - "$CONFIG" <<'PY'
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("knownBulbs="):
        print(line.split("=", 1)[1].strip())
        break
PY
)"
        if [[ "$known" == *"444f8e3c2ed4"* ]]; then
            break
        fi
    fi
    sleep 0.5
done

if [[ ! -f "$MARKER" ]] || ! grep -q '^state ' "$MARKER"; then
    echo "FALLO: no se consultó el estado de la bombilla conocida" >&2
    cat "$LOG" >&2
    exit 1
fi

if ! grep -q '^discover$' "$MARKER"; then
    echo "FALLO: no se lanzó el descubrimiento tras quedar todo sin conexión" >&2
    cat "$MARKER" >&2
    exit 1
fi

if [[ "$known" != *"444f8e318dc4"* ]]; then
    echo "FALLO: el descubrimiento eliminó la bombilla conocida 444F8E318DC4" >&2
    echo "knownBulbs=$known" >&2
    exit 1
fi

if [[ "$known" != *"444f8e3c2ed4"* ]]; then
    echo "FALLO: el descubrimiento no añadió la bombilla nueva 444F8E3C2ED4" >&2
    echo "knownBulbs=$known" >&2
    exit 1
fi

echo "OK: el descubrimiento conserva las bombillas conocidas"
