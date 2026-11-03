#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLET_ID="org.neikon.neiwiz"

main_qml="$ROOT/plasmoid/contents/ui/main.qml"
for token in ExecRunner knownBulbs refreshState; do
    if ! grep -q "$token" "$main_qml"; then
        echo "FALLO: main.qml no contiene $token" >&2
        exit 1
    fi
done

if ! kpackagetool6 --type Plasma/Applet --upgrade "$ROOT/plasmoid" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --install "$ROOT/plasmoid" >/dev/null
fi

if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    echo "SKIP: no hay un servidor gráfico disponible"
    exit 0
fi

log="$(mktemp)"
cleanup() {
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -f "$log"
}
trap cleanup EXIT

QT_FORCE_STDERR_LOGGING=1 timeout 8s plasmawindowed "$APPLET_ID" >"$log" 2>&1 &
pid=$!
sleep 4

if ! kill -0 "$pid" 2>/dev/null; then
    cat "$log"
    echo "FALLO: plasmawindowed terminó antes de tiempo" >&2
    exit 1
fi

if grep -Eqi 'QQmlApplicationEngine failed|is not a type|Cannot assign|ReferenceError|TypeError|SyntaxError|[Ee]rror:|failed to load|error when loading applet|\.qml:[0-9]+:' "$log"; then
    cat "$log"
    echo "FALLO: errores QML al cargar el plasmoid" >&2
    exit 1
fi

echo "OK: el plasmoid carga"
