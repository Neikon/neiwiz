#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_DATA="$TMP_HOME/xdg-data"
LOG="$(mktemp)"
MARKER="$TMP_HOME/helper-called"
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

cat > "$TMP_DATA/neiwiz/wizhelper.py" <<'PY'
import json
import os
import sys

with open(os.environ["NEIWIZ_TEST_MARKER"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(sys.argv[1:]) + "\n")

print(json.dumps({"ok": True, "bulbs": []}))
PY

XDG_DATA_HOME="$TMP_DATA" kpackagetool6 --type Plasma/Applet \
    --install "$ROOT/plasmoid" >/dev/null

HOME="$TMP_HOME" \
XDG_CONFIG_HOME="$TMP_HOME/.config" \
XDG_CACHE_HOME="$TMP_HOME/.cache" \
XDG_DATA_HOME="$TMP_DATA" \
NEIWIZ_TEST_MARKER="$MARKER" \
QT_FORCE_STDERR_LOGGING=1 \
QT_LOGGING_RULES="qml.debug=true" \
plasmawindowed org.neikon.neiwiz >"$LOG" 2>&1 &
PID=$!

found=0
for _ in $(seq 1 40); do
    if [[ -f "$MARKER" ]] && grep -qx 'discover' "$MARKER"; then
        found=1
        break
    fi
    sleep 0.5
done

if [[ "$found" -ne 1 ]]; then
    echo "FAIL: the helper was not run with discover; calls:" >&2
    if [[ -f "$MARKER" ]]; then
        cat "$MARKER" >&2
    else
        cat "$LOG" >&2
    fi
    exit 1
fi

echo "OK: el helper por defecto se ejecuta (discover)"
