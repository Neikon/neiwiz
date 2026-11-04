#!/usr/bin/env python3
"""NeiWiz one-shot helper: discover and control WiZ bulbs over the LAN.

This module is imported by the test suite and executed as a short-lived CLI by
the Plasma applet. It never keeps a socket open after returning.
"""

from __future__ import annotations

import argparse
import asyncio
import fcntl
import ipaddress
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import pywizlight
from pywizlight import PilotBuilder, bulb, wizlight as WizLight
from pywizlight.discovery import find_wizlights
from pywizlight.exceptions import WizLightTimeOutError


# pywizlight reads this module-level timeout when it waits for a bulb reply.
# The default (13 s) would keep the applet's one-shot helper alive too long.
bulb.TIMEOUT = 2.0

BULB_TIMEOUT = 2.5
DISCOVERY_WAIT = 2.0
DISCOVERY_TIMEOUT = 4.0
GLOBAL_BROADCAST = "255.255.255.255"

MAC_RE = re.compile(r"[0-9a-fA-F]{12}")
INET_RE = re.compile(r"\binet\s+(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})\b")


def safe_ip(value: str) -> str | None:
    """Return a normalized IPv4 address or None if the value is not one."""
    try:
        return str(ipaddress.IPv4Address(value))
    except (ipaddress.AddressValueError, ValueError, TypeError):
        return None


def safe_mac(value: object) -> str | None:
    """Return a lowercase 12-hex-digit MAC or None if it is not one."""
    if not isinstance(value, str):
        return None
    compact = re.sub(r"[\s:.-]", "", value)
    if not MAC_RE.fullmatch(compact):
        return None
    return compact.lower()


NAMES_FILE = "bulb-names.json"


def names_path() -> Path:
    """Return the stable per-user file for custom bulb names."""
    config_home = os.environ.get("XDG_CONFIG_HOME")
    base = Path(config_home) if config_home else Path.home() / ".config"
    return base / "neiwiz" / NAMES_FILE


def _read_names_file(source: Path) -> dict[str, str]:
    data = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("el archivo no contiene un objeto JSON")

    names: dict[str, str] = {}
    for key, value in data.items():
        mac = safe_mac(key)
        if mac is None or not isinstance(value, str):
            continue
        name = value.strip()
        if name:
            names[mac] = name
    return names


def load_names(path: Path | None = None) -> dict[str, str]:
    """Read custom names, ignoring missing, corrupt or invalid entries."""
    source = names_path() if path is None else path
    try:
        return _read_names_file(source)
    except (OSError, ValueError):
        return {}


def save_names(names: dict[str, str], path: Path | None = None) -> None:
    """Write names atomically so a crash cannot truncate the file."""
    target = names_path() if path is None else path
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(
        json.dumps(names, ensure_ascii=False, sort_keys=True), encoding="utf-8"
    )
    temporary.replace(target)


def set_name(mac: str, name: str, path: Path | None = None) -> dict[str, Any]:
    """Save a name, or delete it when the name is empty."""
    clean = safe_mac(mac)
    if clean is None:
        return {"ok": False, "error": "MAC no válida"}

    target = names_path() if path is None else path
    target.parent.mkdir(parents=True, exist_ok=True)
    lock_path = target.with_name(target.name + ".lock")
    with lock_path.open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            names = _read_names_file(target)
        except FileNotFoundError:
            names = {}
        except (OSError, ValueError) as exc:
            return {"ok": False, "error": f"No se pudo leer la lista de nombres: {exc}"}
        trimmed = str(name or "").strip()
        if trimmed:
            names[clean] = trimmed
        else:
            names.pop(clean, None)
        save_names(names, target)
    return {"ok": True, "names": names}


def _fix_name_option(argv: list[str]) -> list[str]:
    """Turn `--name -luz` into `--name=-luz` so argparse accepts the value."""
    fixed: list[str] = []
    index = 0
    while index < len(argv):
        value = argv[index]
        if (
            value == "--name"
            and index + 1 < len(argv)
            and argv[index + 1].startswith("-")
            and argv[index + 1] != "-"
        ):
            fixed.append(f"--name={argv[index + 1]}")
            index += 2
            continue
        fixed.append(value)
        index += 1
    return fixed


def percent_to_raw(percent: int) -> int:
    """Map a 1..100 brightness percentage to the WiZ 1..255 raw range."""
    value = max(1, min(100, int(percent)))
    return max(1, min(255, (value * 255 + 50) // 100))


def parse_pilot_result(result: dict[str, Any] | None) -> dict[str, Any]:
    """Normalize a pywizlight getPilot response for the applet contract."""
    data = result or {}
    try:
        brightness = int(data.get("dimming", 100))
    except (TypeError, ValueError):
        brightness = 100
    brightness = max(1, min(100, brightness))
    return {
        "on": bool(data.get("state", False)),
        "brightness": brightness,
        "mac": safe_mac(data.get("mac")),
    }


def local_broadcasts() -> list[str]:
    """Return every unique broadcast address of global IPv4 interfaces."""
    try:
        completed = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", "scope", "global"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        )
    except (OSError, subprocess.SubprocessError):
        return []

    broadcasts: list[str] = []
    for line in completed.stdout.splitlines():
        match = INET_RE.search(line)
        if not match:
            continue
        address, prefix = match.groups()
        try:
            interface = ipaddress.IPv4Interface(f"{address}/{prefix}")
        except ValueError:
            continue
        broadcast = str(interface.network.broadcast_address)
        if broadcast not in broadcasts:
            broadcasts.append(broadcast)
    return broadcasts


def _error_text(exc: BaseException) -> str:
    return str(exc) or type(exc).__name__


async def _close(bulb_instance: Any) -> None:
    try:
        await bulb_instance.async_close()
    except Exception:
        pass


async def query_bulb(ip: str) -> dict[str, Any]:
    """Query one bulb and always return an applet-friendly state row."""
    device = WizLight(ip)
    try:
        states = await asyncio.wait_for(device.updateState(), timeout=BULB_TIMEOUT)
        state = states[0] if states else None
        if state is None:
            raise WizLightTimeOutError("respuesta vacía")
        return {"ip": ip, "online": True, **parse_pilot_result(state.pilotResult)}
    except Exception as exc:
        return {
            "ip": ip,
            "online": False,
            "on": False,
            "brightness": 100,
            "mac": None,
            "error": _error_text(exc),
        }
    finally:
        await _close(device)


async def query_many(ips: list[str]) -> list[dict[str, Any]]:
    """Query several bulbs concurrently, never letting one block the rest."""
    normalized: list[str] = []
    for ip in ips:
        value = safe_ip(ip)
        if value is not None and value not in normalized:
            normalized.append(value)

    results = await asyncio.gather(
        *(query_bulb(ip) for ip in normalized), return_exceptions=True
    )
    bulbs: list[dict[str, Any]] = []
    for ip, result in zip(normalized, results):
        if isinstance(result, BaseException):
            bulbs.append(
                {
                    "ip": ip,
                    "online": False,
                    "on": False,
                    "brightness": 100,
                    "mac": None,
                    "error": _error_text(result),
                }
            )
        else:
            bulbs.append(result)
    return bulbs


async def _find_on(address: str) -> list[Any]:
    try:
        return await asyncio.wait_for(
            find_wizlights(wait_time=DISCOVERY_WAIT, broadcast_address=address),
            timeout=DISCOVERY_TIMEOUT,
        )
    except Exception:
        return []


async def discover_bulbs() -> list[dict[str, Any]]:
    """Broadcast for bulbs, then read their current state."""
    addresses = [GLOBAL_BROADCAST]
    for address in local_broadcasts():
        if address not in addresses:
            addresses.append(address)

    discovered: list[Any] = []
    for address in addresses:
        discovered = await _find_on(address)
        if discovered:
            break

    by_ip: dict[str, Any] = {}
    for found in discovered:
        ip = safe_ip(getattr(found, "ip_address", None))
        if ip is not None and ip not in by_ip:
            by_ip[ip] = found

    if not by_ip:
        return []

    states = await query_many(list(by_ip))
    for state in states:
        bulb_info = by_ip.get(state["ip"])
        if bulb_info is not None and not state.get("mac"):
            state["mac"] = safe_mac(getattr(bulb_info, "mac_address", None))
    return states


async def set_bulb(ip: str, action: str, value: int | None = None) -> dict[str, Any]:
    """Send one power or brightness command to a bulb."""
    device = WizLight(ip)
    try:
        if action == "on":
            await asyncio.wait_for(device.turn_on(), timeout=BULB_TIMEOUT)
        elif action == "off":
            await asyncio.wait_for(device.turn_off(), timeout=BULB_TIMEOUT)
        elif action == "brightness":
            if value is None:
                return {"ok": False, "error": "falta el valor de brillo"}
            raw = percent_to_raw(value)
            await asyncio.wait_for(
                device.turn_on(PilotBuilder(brightness=raw)), timeout=BULB_TIMEOUT
            )
        else:
            return {"ok": False, "error": f"acción desconocida: {action}"}
        return {"ok": True, "ip": ip}
    except Exception as exc:
        return {"ok": False, "error": _error_text(exc)}
    finally:
        await _close(device)


def _emit(payload: dict[str, Any], exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return exit_code


def main(argv: list[str] | None = None) -> int:
    """Run the helper CLI and print exactly one JSON object on stdout."""
    parser = argparse.ArgumentParser(prog="wizhelper")
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("discover", help="buscar bombillas WiZ en la red")
    commands.add_parser("names", help="leer los nombres personalizados")

    name_parser = commands.add_parser("set-name", help="guardar o borrar un nombre")
    name_parser.add_argument("--mac", required=True)
    name_parser.add_argument("--name", default="")

    state_parser = commands.add_parser("state", help="consultar bombillas conocidas")
    state_parser.add_argument("--ip", action="append", required=True, dest="ips")

    set_parser = commands.add_parser("set", help="encender, apagar o regular")
    set_parser.add_argument("--ip", required=True)
    action = set_parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--on", action="store_true")
    action.add_argument("--off", action="store_true")
    action.add_argument("--brightness", type=int)

    raw = sys.argv[1:] if argv is None else argv
    args = parser.parse_args(_fix_name_option(raw))

    try:
        if args.command == "discover":
            return _emit({"ok": True, "bulbs": asyncio.run(discover_bulbs())})

        if args.command == "names":
            return _emit({"ok": True, "names": load_names()})

        if args.command == "set-name":
            return _emit(set_name(args.mac, args.name))

        if args.command == "state":
            normalized = [safe_ip(ip) for ip in args.ips]
            if any(ip is None for ip in normalized):
                return _emit({"ok": False, "error": "dirección IP no válida"})
            ips = [ip for ip in normalized if ip is not None]
            return _emit({"ok": True, "bulbs": asyncio.run(query_many(ips))})

        ip = safe_ip(args.ip)
        if ip is None:
            return _emit({"ok": False, "error": "dirección IP no válida"})

        if args.on:
            action_name, value = "on", None
        elif args.off:
            action_name, value = "off", None
        else:
            action_name, value = "brightness", args.brightness

        result = asyncio.run(set_bulb(ip, action_name, value))
        if not isinstance(result, dict):
            result = {"ok": True, "ip": ip}
        return _emit(result)
    except Exception as exc:
        return _emit({"ok": False, "error": _error_text(exc)}, exit_code=1)


if __name__ == "__main__":
    raise SystemExit(main())
