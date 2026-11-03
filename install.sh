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
    || fail "no se encontró kpackagetool6; ¿está instalado Plasma 6?"

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
            # Sin python3 en PATH, deja que uv elija o descargue un intérprete.
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
        printf '%s\n' "pywizlight falló con $( "$VENV_PYTHON" -V 2>&1 ); recreando el entorno con Python 3.13 gestionado por uv…"
        create_venv 3.13
        install_python_deps || fail "no se pudo instalar pywizlight ni con Python 3.13."
    else
        fail "no se pudo instalar pywizlight. Instala uv (https://docs.astral.sh/uv/) y vuelve a ejecutar install.sh."
    fi
fi

install -m 0644 "$ROOT/helper/wizhelper.py" "$HELPER"

if ! kpackagetool6 --type Plasma/Applet --upgrade "$PLASMOID" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --install "$PLASMOID" >/dev/null
fi

cat <<EOF
NeiWiz instalado correctamente.

Añádelo a la bandeja del sistema:
  1. Clic derecho en la bandeja de Plasma.
  2. Elige «Configurar la bandeja del sistema…».
  3. En «Entradas del sistema», activa NeiWiz.

Para actualizar, vuelve a ejecutar ./install.sh.
La configuración del applet (bombillas conocidas) se conserva.

Comprueba el descubrimiento con:
  "$VENV_PYTHON" "$HELPER" discover

El helper y su entorno están en:
  $DATA_DIR
EOF
