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
    sys.exit("Missing plasmoid files: " + ", ".join(missing))

try:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as error:
    sys.exit(f"metadata.json is not valid JSON: {error}")

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
        sys.exit(f"{key}: expected {value!r}, found {checks[key]!r}")

config = (root / "plasmoid" / "contents" / "config" / "main.xml").read_text(encoding="utf-8")
for key in ("knownBulbs", "helperCommand", "helperScript"):
    if f'name="{key}"' not in config:
        sys.exit(f"Missing configuration key {key}")
if "$HOME/.local/share" in config:
    sys.exit("main.xml must not hardcode $HOME paths; the QML resolves XDG_DATA_HOME")

main_qml = (root / "plasmoid" / "contents" / "ui" / "main.qml").read_text(encoding="utf-8")
for token in ("PlasmoidItem", "compactRepresentation", "fullRepresentation"):
    if token not in main_qml:
        sys.exit(f"main.qml does not contain {token}")
if "StandardPaths.GenericDataLocation" not in main_qml:
    sys.exit("main.qml does not resolve the helper path with StandardPaths.GenericDataLocation")

print("OK: plasmoid package is valid")
PY
