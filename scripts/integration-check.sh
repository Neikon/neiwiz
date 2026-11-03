#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz"

for script in install.sh uninstall.sh; do
    if [[ ! -f "$ROOT/$script" ]]; then
        echo "FALLO: falta $script" >&2
        exit 1
    fi
    bash -n "$ROOT/$script"
done

bash "$ROOT/install.sh"

json="$("$DATA_DIR/venv/bin/python" "$DATA_DIR/wizhelper.py" discover)"
printf '%s\n' "$json" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True:
    raise SystemExit("FALLO: discover no devolvió ok=true: %r" % (payload,))

bulbs = payload.get("bulbs") or []
print("Bombillas descubiertas: %d" % len(bulbs))
for bulb in bulbs:
    state = "encendida" if bulb.get("on") else "apagada"
    print("  - %s (%s, %s)" % (bulb.get("ip"), bulb.get("mac", "?"), state))
'

bash "$ROOT/scripts/smoke-plasmoid.sh"
bash "$ROOT/scripts/default-path-check.sh"
