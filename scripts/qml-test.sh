#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! python3 -c 'import PySide6.QtQuickTest' >/dev/null 2>&1; then
    echo "FALLO: faltan los módulos QML de PySide6 (python3-pyside6)." >&2
    exit 2
fi

QT_QPA_PLATFORM=offscreen python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
from PySide6.QtQuickTest import QUICK_TEST_MAIN

root = Path(sys.argv[1])
raise SystemExit(QUICK_TEST_MAIN("neiwiz", [sys.argv[0]], str(root / "tests" / "qml")))
PY
