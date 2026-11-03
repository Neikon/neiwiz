#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata_path = root / "plasmoid" / "metadata.json"

missing = []
for relative in [
    "plasmoid/contents/ui/main.qml",
    "plasmoid/contents/ui/FullRepresentation.qml",
    "plasmoid/contents/config/main.xml",
]:
    if not (root / relative).is_file():
        missing.append(relative)

if missing:
    sys.exit("Faltan archivos del plasmoid: " + ", ".join(missing))

try:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as error:
    sys.exit(f"metadata.json no es JSON válido: {error}")

plugin = metadata.get("KPlugin", {})
checks = {
    "KPackageStructure": metadata.get("KPackageStructure"),
    "KPlugin.Id": plugin.get("Id"),
    "KPlugin.Name": plugin.get("Name"),
    "X-Plasma-API-Minimum-Version": metadata.get("X-Plasma-API-Minimum-Version"),
    "X-Plasma-NotificationAreaCategory": metadata.get("X-Plasma-NotificationAreaCategory"),
}
expected = {
    "KPackageStructure": "Plasma/Applet",
    "KPlugin.Id": "org.neikon.neiwiz",
    "KPlugin.Name": "NeiWiz",
    "X-Plasma-API-Minimum-Version": "6.0",
    "X-Plasma-NotificationAreaCategory": "Hardware",
}
for key, value in expected.items():
    if checks[key] != value:
        sys.exit(f"{key}: se esperaba {value!r}, se encontró {checks[key]!r}")

config = (root / "plasmoid" / "contents" / "config" / "main.xml").read_text(encoding="utf-8")
for key in ("knownBulbs", "helperCommand", "helperScript"):
    if f'name="{key}"' not in config:
        sys.exit(f"Falta la clave de configuración {key}")

main_qml = (root / "plasmoid" / "contents" / "ui" / "main.qml").read_text(encoding="utf-8")
for token in ("PlasmoidItem", "compactRepresentation", "fullRepresentation"):
    if token not in main_qml:
        sys.exit(f"main.qml no contiene {token}")

print("OK: paquete del plasmoid válido")
PY
