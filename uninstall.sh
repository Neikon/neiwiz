#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/neiwiz"
APPLET_ID="org.neikon.neiwiz"

command -v kpackagetool6 >/dev/null 2>&1 \
    || printf 'Warning: kpackagetool6 not found; skipping plasmoid removal.\n' >&2

if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
        kpackagetool6 --type Plasma/Applet --remove "$APPLET_ID"
    else
        printf '%s\n' "The plasmoid $APPLET_ID was not installed in Plasma."
    fi
fi

if [[ -d "$DATA_DIR" ]]; then
    rm -rf "$DATA_DIR"
    printf '%s\n' "Removed the helper and its environment: $DATA_DIR"
else
    printf '%s\n' "The helper was not installed in $DATA_DIR."
fi

cat <<'EOF'
NeiWiz uninstalled.
The applet configuration is preserved; to remove it, delete the widget entry
in the system tray and, optionally, its group in
~/.config/plasma-org.kde.plasma.desktop-appletsrc.
EOF
