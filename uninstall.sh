#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz"
APPLET_ID="org.neikon.neiwiz"

command -v kpackagetool6 >/dev/null 2>&1 \
    || printf 'Aviso: no se encontró kpackagetool6; se omite la retirada del plasmoid.\n' >&2

if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
        kpackagetool6 --type Plasma/Applet --remove "$APPLET_ID"
    else
        printf '%s\n' "El plasmoid $APPLET_ID no estaba instalado en Plasma."
    fi
fi

if [[ -d "$DATA_DIR" ]]; then
    rm -rf "$DATA_DIR"
    printf '%s\n' "Eliminado el helper y su entorno: $DATA_DIR"
else
    printf '%s\n' "El helper no estaba instalado en $DATA_DIR."
fi

cat <<'EOF'
NeiWiz desinstalado.
La configuración del applet se conserva; si quieres eliminarla, borra la
entrada del widget en la bandeja y, opcionalmente, su grupo en
~/.config/plasma-org.kde.plasma.desktop-appletsrc.
EOF
