from pathlib import Path
import importlib.util
import subprocess

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


def test_local_broadcast_parses_ip_addr(helper, monkeypatch):
    output = (
        "2: eno1    inet 192.168.1.250/24 brd 192.168.1.255 scope global eno1\\"
        "       valid_lft forever preferred_lft forever"
    )
    completed = subprocess.CompletedProcess(args=[], returncode=0, stdout=output, stderr="")
    monkeypatch.setattr(helper.subprocess, "run", lambda *args, **kwargs: completed)
    assert helper.local_broadcast() == "192.168.1.255"


def test_local_broadcast_returns_none_when_command_fails(helper, monkeypatch):
    def raise_error(*args, **kwargs):
        raise subprocess.CalledProcessError(1, "ip")

    monkeypatch.setattr(helper.subprocess, "run", raise_error)
    assert helper.local_broadcast() is None
