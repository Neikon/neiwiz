#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz"
VENV="$DATA_DIR/venv"
VENV_PYTHON="$VENV/bin/python"
HELPER="$DATA_DIR/wizhelper.py"
PLASMOID="$ROOT/plasmoid"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command -v kpackagetool6 >/dev/null 2>&1 \
    || fail "kpackagetool6 not found; is Plasma 6 installed?"

mkdir -p "$DATA_DIR"

venv_ready() {
    [[ -x "$VENV_PYTHON" ]] && "$VENV_PYTHON" -c 'import sys' >/dev/null 2>&1
}

create_venv() {
    local python_version="${1:-}"
    local system_python=""

    rm -rf "$VENV"

    if command -v uv >/dev/null 2>&1; then
        if [[ -n "$python_version" ]]; then
            uv venv --python "$python_version" "$VENV"
            return
        fi
        system_python="$(command -v python3 || true)"
        if [[ -n "$system_python" ]]; then
            uv venv --python "$system_python" "$VENV"
        else
            # Without python3 in PATH, let uv pick or download an interpreter.
            uv venv "$VENV"
        fi
    else
        python3 -m venv "$VENV"
    fi
}

install_python_deps() {
    if command -v uv >/dev/null 2>&1; then
        uv pip install --python "$VENV_PYTHON" -r "$ROOT/requirements.txt"
    else
        "$VENV_PYTHON" -m pip install --disable-pip-version-check -r "$ROOT/requirements.txt"
    fi
    "$VENV_PYTHON" -c 'import pywizlight'
}

if ! venv_ready; then
    create_venv
fi

if ! install_python_deps; then
    if command -v uv >/dev/null 2>&1; then
        printf '%s\n' "pywizlight failed with $( "$VENV_PYTHON" -V 2>&1 ); recreating the environment with uv-managed Python 3.13…"
        create_venv 3.13
        install_python_deps || fail "could not install pywizlight even with Python 3.13."
    else
        fail "could not install pywizlight. Install uv (https://docs.astral.sh/uv/) and run install.sh again."
    fi
fi

install -m 0644 "$ROOT/helper/wizhelper.py" "$HELPER"

if ! kpackagetool6 --type Plasma/Applet --upgrade "$PLASMOID" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --install "$PLASMOID" >/dev/null
fi

cat <<EOF
NeiWiz installed successfully.

Add it to the system tray:
  1. Right-click the Plasma tray.
  2. Choose “Configure System Tray…”.
  3. Under “System Entries”, enable NeiWiz.

To update, run ./install.sh again.
The applet configuration (known bulbs) is preserved.

Check discovery with:
  "$VENV_PYTHON" "$HELPER" discover

The helper and its environment are in:
  $DATA_DIR
EOF
