#!/usr/bin/env python3
"""NeiWiz one-shot helper: discover and control WiZ bulbs over the LAN.

This module is imported by the test suite and executed as a short-lived CLI by
the Plasma applet. It never keeps a socket open after returning.
"""

from __future__ import annotations

import ipaddress
import re
import subprocess
from typing import Any

import pywizlight


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


def local_broadcast() -> str | None:
    """Return the broadcast address of the first global IPv4 interface."""
    try:
        completed = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", "scope", "global"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        )
    except (OSError, subprocess.SubprocessError):
        return None

    if completed.returncode != 0:
        return None

    for line in completed.stdout.splitlines():
        match = INET_RE.search(line)
        if not match:
            continue
        address, prefix = match.groups()
        try:
            interface = ipaddress.IPv4Interface(f"{address}/{prefix}")
        except ValueError:
            continue
        return str(interface.network.broadcast_address)
    return None
