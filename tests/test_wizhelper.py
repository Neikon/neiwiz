from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import asyncio
import importlib.util
import json
import subprocess
import threading
import time
from types import SimpleNamespace

import pytest


HELPER_PATH = Path(__file__).resolve().parents[1] / "helper" / "wizhelper.py"


@pytest.fixture
def helper():
    if not HELPER_PATH.is_file():
        pytest.fail(f"no existe el helper: {HELPER_PATH}")
    spec = importlib.util.spec_from_file_location("wizhelper", HELPER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    ("percent", "expected"),
    [
        (1, 3),
        (50, 128),
        (100, 255),
        (0, 3),
        (-10, 3),
        (101, 255),
        (999, 255),
    ],
)
def test_percent_to_raw(helper, percent, expected):
    assert helper.percent_to_raw(percent) == expected


def test_parse_pilot_result_on(helper):
    assert helper.parse_pilot_result(
        {"state": True, "dimming": 42, "mac": "a8bb50a4f94d"}
    ) == {"on": True, "brightness": 42, "mac": "a8bb50a4f94d"}


def test_parse_pilot_result_off_with_zero_dimming(helper):
    assert helper.parse_pilot_result({"state": False, "dimming": 0}) == {
        "on": False,
        "brightness": 1,
        "mac": None,
    }


def test_parse_pilot_result_missing_dimming_defaults_to_100(helper):
    assert helper.parse_pilot_result({"state": True}) == {
        "on": True,
        "brightness": 100,
        "mac": None,
    }


def test_parse_pilot_result_none_is_off(helper):
    assert helper.parse_pilot_result(None) == {
        "on": False,
        "brightness": 100,
        "mac": None,
    }


def test_safe_ip_accepts_ipv4(helper):
    assert helper.safe_ip("192.168.1.10") == "192.168.1.10"


@pytest.mark.parametrize("value", ["999.1.1.1", "example.com", "::1", "", None])
def test_safe_ip_rejects_invalid(helper, value):
    assert helper.safe_ip(value) is None


def test_safe_mac_accepts_compact_uppercase(helper):
    assert helper.safe_mac("A8BB50A4F94D") == "a8bb50a4f94d"


def test_safe_mac_accepts_colon_separated(helper):
    assert helper.safe_mac("a8:bb:50:a4:f9:4d") == "a8bb50a4f94d"


@pytest.mark.parametrize("value", ["A8BB50", "garbage", "a8:bb:50:a4:f9:zz", None, 12345])
def test_safe_mac_rejects_invalid(helper, value):
    assert helper.safe_mac(value) is None


def test_local_broadcasts_parses_all_unique_interfaces(helper, monkeypatch):
    output = (
        "2: eno1    inet 192.168.1.250/24 brd 192.168.1.255 scope global eno1\\"
        "       valid_lft forever preferred_lft forever\n"
        "3: wlan0   inet 10.0.0.5/24 brd 10.0.0.255 scope global wlan0\\"
        "       valid_lft forever preferred_lft forever\n"
        "4: eno1    inet 192.168.1.250/24 brd 192.168.1.255 scope global eno1\\"
        "       valid_lft forever preferred_lft forever\n"
    )
    completed = subprocess.CompletedProcess(args=[], returncode=0, stdout=output, stderr="")
    monkeypatch.setattr(helper.subprocess, "run", lambda *args, **kwargs: completed)
    assert helper.local_broadcasts() == ["192.168.1.255", "10.0.0.255"]


def test_local_broadcasts_returns_empty_when_command_fails(helper, monkeypatch):
    def raise_error(*args, **kwargs):
        raise subprocess.CalledProcessError(1, "ip")

    monkeypatch.setattr(helper.subprocess, "run", raise_error)
    assert helper.local_broadcasts() == []


def test_query_many_marks_timeouts_offline(helper, monkeypatch):
    async def timeout(ip):
        raise helper.WizLightTimeOutError("sin respuesta")

    monkeypatch.setattr(helper, "query_bulb", timeout)
    result = asyncio.run(helper.query_many(["192.168.1.10"]))

    assert len(result) == 1
    assert result[0]["ip"] == "192.168.1.10"
    assert result[0]["online"] is False
    assert result[0]["error"]


def test_discover_uses_global_then_local_broadcast(helper, monkeypatch):
    addresses = []
    fake_bulb = SimpleNamespace(ip_address="192.168.1.10", mac_address="a8bb50a4f94d")

    async def fake_find(wait_time, broadcast_address):
        addresses.append(broadcast_address)
        if broadcast_address in ("255.255.255.255", "192.168.1.255"):
            return []
        return [fake_bulb]

    async def fake_query_many(ips):
        return [
            {
                "ip": ips[0],
                "online": True,
                "on": True,
                "brightness": 80,
                "mac": None,
            }
        ]

    monkeypatch.setattr(helper, "find_wizlights", fake_find)
    monkeypatch.setattr(helper, "query_many", fake_query_many)
    monkeypatch.setattr(helper, "local_broadcasts", lambda: ["192.168.1.255", "10.0.0.255"])

    result = asyncio.run(helper.discover_bulbs())

    assert addresses == ["255.255.255.255", "192.168.1.255", "10.0.0.255"]
    assert len(result) == 1
    assert result[0]["ip"] == "192.168.1.10"
    assert result[0]["mac"] == "a8bb50a4f94d"


def test_main_state_outputs_json(helper, monkeypatch, capsys):
    async def fake_query_many(ips):
        return [
            {
                "ip": ips[0],
                "online": True,
                "on": True,
                "brightness": 50,
                "mac": "a8bb50a4f94d",
            }
        ]

    monkeypatch.setattr(helper, "query_many", fake_query_many)
    code = helper.main(["state", "--ip", "192.168.1.10"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["ok"] is True
    assert len(payload["bulbs"]) == 1
    assert payload["bulbs"][0]["brightness"] == 50


def test_main_state_skips_invalid_saved_ips(helper, monkeypatch, capsys):
    calls = []

    async def fake_query_many(ips):
        calls.append(ips)
        return [{"ip": ips[0], "online": True, "on": False, "brightness": 100, "mac": None}]

    monkeypatch.setattr(helper, "query_many", fake_query_many)
    code = helper.main(["state", "--ip", "not-an-ip", "--ip", "192.168.1.10"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["ok"] is True
    assert calls == [["192.168.1.10"]]


def test_main_state_rejects_when_all_ips_are_invalid(helper, capsys):
    code = helper.main(["state", "--ip", "not-an-ip"])

    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is False
    assert payload["error"]


def test_main_set_brightness_maps_percent(helper, monkeypatch, capsys):
    calls = []

    async def fake_set(ip, action, value=None):
        calls.append((ip, action, value))
        return {"ok": True, "ip": ip}

    monkeypatch.setattr(helper, "set_bulb", fake_set)
    code = helper.main(["set", "--ip", "192.168.1.10", "--brightness", "50"])

    capsys.readouterr()
    assert code == 0
    assert calls == [("192.168.1.10", "brightness", 50)]


def test_main_rejects_invalid_ip(helper, capsys):
    code = helper.main(["set", "--ip", "not-an-ip", "--on"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["ok"] is False
    assert payload["error"]


def test_main_set_on_and_off_actions(helper, monkeypatch, capsys):
    calls = []

    async def fake_set(ip, action, value=None):
        calls.append((ip, action))
        return {"ok": True, "ip": ip}

    monkeypatch.setattr(helper, "set_bulb", fake_set)
    helper.main(["set", "--ip", "192.168.1.10", "--on"])
    helper.main(["set", "--ip", "192.168.1.10", "--off"])

    capsys.readouterr()
    assert calls == [("192.168.1.10", "on"), ("192.168.1.10", "off")]


def test_main_discover_with_no_bulbs(helper, monkeypatch, capsys):
    async def fake_discover():
        return []

    monkeypatch.setattr(helper, "discover_bulbs", fake_discover)
    code = helper.main(["discover"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload == {"ok": True, "bulbs": []}


def test_names_path_uses_xdg_config_home(helper, monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    assert helper.names_path() == tmp_path / "neiwiz" / "bulb-names.json"


def test_names_path_falls_back_to_home(helper, monkeypatch, tmp_path):
    monkeypatch.delenv("XDG_CONFIG_HOME", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    assert helper.names_path() == tmp_path / ".config" / "neiwiz" / "bulb-names.json"


def test_save_and_load_names_roundtrip(helper, tmp_path):
    path = tmp_path / "names.json"
    helper.save_names({"AABBCCDDEEFF": "Despacho"}, path)
    assert helper.load_names(path) == {"aabbccddeeff": "Despacho"}


@pytest.mark.parametrize("content", ["{not json", '["not", "an", "object"]'])
def test_load_names_ignores_invalid_file(helper, tmp_path, content):
    path = tmp_path / "names.json"
    path.write_text(content, encoding="utf-8")
    assert helper.load_names(path) == {}


def test_load_names_filters_invalid_entries(helper, tmp_path):
    path = tmp_path / "names.json"
    path.write_text(
        json.dumps(
            {
                "AA:BB:CC:DD:EE:FF": "Despacho",
                "not-a-mac": "Cocina",
                "AABBCCDDEEFF": "   ",
                "112233445566": 42,
            }
        ),
        encoding="utf-8",
    )
    assert helper.load_names(path) == {"aabbccddeeff": "Despacho"}


def test_set_name_saves_and_deletes(helper, tmp_path):
    path = tmp_path / "names.json"

    result = helper.set_name("AA:BB:CC:DD:EE:FF", "  Despacho  ", path)
    assert result["ok"] is True
    assert helper.load_names(path) == {"aabbccddeeff": "Despacho"}

    result = helper.set_name("aabbccddeeff", "   ", path)
    assert result["ok"] is True
    assert helper.load_names(path) == {}


def test_set_name_rejects_invalid_mac(helper, tmp_path):
    result = helper.set_name("not-a-mac", "Despacho", tmp_path / "names.json")
    assert result["ok"] is False
    assert "MAC" in result["error"]


def test_main_names_outputs_json(helper, monkeypatch, capsys, tmp_path):
    path = tmp_path / "names.json"
    helper.save_names({"aabbccddeeff": "Despacho"}, path)
    monkeypatch.setattr(helper, "names_path", lambda: path)

    code = helper.main(["names"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload == {"ok": True, "names": {"aabbccddeeff": "Despacho"}}


def test_main_set_name_outputs_json(helper, monkeypatch, capsys, tmp_path):
    path = tmp_path / "names.json"
    monkeypatch.setattr(helper, "names_path", lambda: path)

    code = helper.main(["set-name", "--mac", "AABBCCDDEEFF", "--name", "Despacho"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["ok"] is True
    assert payload["names"] == {"aabbccddeeff": "Despacho"}


def test_main_set_name_accepts_equals_form_with_dash(helper, monkeypatch, capsys, tmp_path):
    path = tmp_path / "names.json"
    monkeypatch.setattr(helper, "names_path", lambda: path)

    code = helper.main(["set-name", "--mac", "AABBCCDDEEFF", "--name=-luz"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["ok"] is True
    assert helper.load_names(path) == {"aabbccddeeff": "-luz"}


def test_set_name_keeps_both_names_when_saves_overlap(helper, tmp_path, monkeypatch):
    path = tmp_path / "names.json"
    original_load = helper.load_names
    start = threading.Barrier(2)

    def slow_load(p=None):
        names = original_load(p)
        time.sleep(0.05)
        return names

    monkeypatch.setattr(helper, "load_names", slow_load)

    def save(mac, name):
        start.wait(timeout=5)
        helper.set_name(mac, name, path)

    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(save, "AABBCCDDEEFF", "Despacho")
        second = pool.submit(save, "112233445566", "Cocina")
        first.result(timeout=5)
        second.result(timeout=5)

    assert helper.load_names(path) == {
        "aabbccddeeff": "Despacho",
        "112233445566": "Cocina",
    }


@pytest.mark.parametrize("content", ["{not json", '["not", "an", "object"]'])
def test_set_name_refuses_to_overwrite_corrupt_file(helper, tmp_path, content):
    path = tmp_path / "names.json"
    path.write_text(content, encoding="utf-8")

    result = helper.set_name("AABBCCDDEEFF", "Despacho", path)

    assert result["ok"] is False
    assert "names file" in result["error"].lower()
    assert path.read_text(encoding="utf-8") == content


def test_set_name_keeps_unrelated_valid_names(helper, tmp_path):
    path = tmp_path / "names.json"
    path.write_text(
        json.dumps({"112233445566": "Cocina", "not-a-mac": "Basura"}),
        encoding="utf-8",
    )

    helper.set_name("AABBCCDDEEFF", "Despacho", path)

    assert helper.load_names(path) == {
        "112233445566": "Cocina",
        "aabbccddeeff": "Despacho",
    }
