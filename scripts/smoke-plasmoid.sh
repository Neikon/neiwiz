#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLET_ID="org.neikon.neiwiz"

ui_dir="$ROOT/plasmoid/contents/ui"
main_qml="$ui_dir/main.qml"
for token in ExecRunner knownBulbs refreshState renameBulb set-name; do
    if ! grep -q "$token" "$main_qml"; then
        echo "FAIL: main.qml does not contain $token" >&2
        exit 1
    fi
done

if ! grep -Fq -- '--name=' "$main_qml"; then
    echo "FAIL: main.qml must pass the name as --name=<value>" >&2
    exit 1
fi

if grep -q 'configuration.bulbNames' "$main_qml"; then
    echo "FAIL: names must not be stored in the applet configuration" >&2
    exit 1
fi

if grep -q 'entry name="bulbNames"' "$ROOT/plasmoid/contents/config/main.xml"; then
    echo "FAIL: config/main.xml still declares bulbNames" >&2
    exit 1
fi

for token in BulbRow renameRequested renameMac Kirigami.PromptDialog PlasmaComponents3.TextField; do
    if ! grep -q "$token" "$ui_dir/FullRepresentation.qml"; then
        echo "FAIL: FullRepresentation.qml does not contain $token" >&2
        exit 1
    fi
done

for token in PlasmaComponents3.Switch PlasmaComponents3.Slider edit-rename renameRequested customName; do
    if ! grep -q "$token" "$ui_dir/BulbRow.qml" 2>/dev/null; then
        echo "FAIL: BulbRow.qml does not contain $token" >&2
        exit 1
    fi
done

for token in "No bulbs found" "engine is missing" "Offline"; do
    if ! grep -Rq "$token" "$ui_dir"; then
        echo "FAIL: state '$token' does not appear in the UI" >&2
        exit 1
    fi
done

if ! kpackagetool6 --type Plasma/Applet --upgrade "$ROOT/plasmoid" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --install "$ROOT/plasmoid" >/dev/null
fi

if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    echo "SKIP: no graphical server available"
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
    echo "FAIL: plasmawindowed exited early" >&2
    exit 1
fi

if grep -Eqi 'QQmlApplicationEngine failed|is not a type|Cannot assign|ReferenceError|TypeError|SyntaxError|[Ee]rror:|failed to load|error when loading applet|\.qml:[0-9]+:' "$log"; then
    cat "$log"
    echo "FAIL: QML errors while loading the plasmoid" >&2
    exit 1
fi

echo "OK: the plasmoid loads"
