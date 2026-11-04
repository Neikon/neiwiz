# NeiWiz Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding from the 2026-11-03 NeiWiz audit without changing the product's scope: a daemonless Plasma 6 tray applet that discovers and controls WiZ bulbs.

**Architecture:** Keep the existing short-lived helper plus QML applet. Fix path resolution by deriving defaults from `StandardPaths`, make renaming follow MAC instead of row position, refuse to overwrite corrupt name files, preserve in-flight row actions during refresh, and move the few testable QML rules into a small JS module.

**Tech Stack:** Plasma 6 QML, `org.kde.plasma.plasma5support`, Python 3.11+, `pywizlight`, `pytest`, Bash, and QtQuick Test through the system PySide6 for QML behavior tests.

**Spec:** `docs/superpowers/specs/2026-11-03-neiwiz-design.md`

## Global Constraints

- Applet name: `NeiWiz`; applet ID: `org.neikon.neiwiz`.
- Target: Plasma 6.7.5 on Bazzite 44; Python 3.11+ (3.14 tested, 3.13 fallback via `uv`).
- No daemon, no systemd unit, no autostart, no listening port, no `sudo`.
- WiZ UDP port: `38899`; the PC and bulbs must share a LAN.
- UI copy in Spanish; helper stdout is JSON only.
- Helper paths must honour `XDG_DATA_HOME`: `<XDG_DATA_HOME>/neiwiz/venv/bin/python` and `<XDG_DATA_HOME>/neiwiz/wizhelper.py`.
- Custom names live in `<XDG_CONFIG_HOME>/neiwiz/bulb-names.json`; key is the normalized lowercase 12-hex MAC.
- `knownBulbs` remains a JSON array of `{ip, mac}` in the applet configuration.
- Tests must not upgrade or modify the live applet; use a temporary `XDG_DATA_HOME`.
- QML behavior tests use `python3` with PySide6's QtQuickTest and `QT_QPA_PLATFORM=offscreen`; PySide6 is a development-only dependency.
- Run `.venv/bin/pytest -q`, `bash scripts/check-plasmoid.sh`, `bash scripts/qml-test.sh` and `git diff --check` before claiming completion.

## Review Focus

- A user with a custom `XDG_DATA_HOME` must still find the helper after install; a path built from `$HOME/.local/share` silently breaks the applet.
- Renaming a bulb while discovery reorders or removes rows must update the MAC the dialog was opened for, never the row that later occupies that position.
- A malformed `bulb-names.json` must make renaming fail visibly and leave the file byte-for-byte untouched; it must never erase the other custom names.
- A refresh that overlaps a toggle or brightness change must not overwrite the in-flight optimistic value or clear the row's busy state.
- A slow discovery on a machine with more than one interface must not be killed by the applet's command timeout.

---

## Findings Coverage

| Audit finding | Owning task |
| --- | --- |
| 1. XDG path mismatch | Task 1 |
| 2. Rename keyed by row index | Task 2 |
| 3. Corrupt names file gets overwritten | Task 3 |
| 4. Refresh overwrites in-flight row actions | Task 4 |
| 5. Hard 8 s command timeout | Task 5 |
| 6. Slider ignores keyboard/wheel commits and has no accessible name | Task 6 |
| 7. Riskiest QML logic has no behavior test | Tasks 2, 4, 5 and 6 add QtQuick Test coverage |
| 8. Local broadcast uses only the first interface | Task 7 |
| 9. `_fix_name_option` hack | Task 8 |
| 10. Dead/duplicate code | Tasks 7, 8 and 9 |
| 11. Completed 345-line plan is dead weight | Task 9 |
| Stale error banner after a successful action | Task 4 |
| «Sin conexión» during the first state query | Task 9 |
| One bad saved IP rejects the whole `state` call | Task 8 |

## File Structure

- `plasmoid/contents/ui/main.qml` — applet state, persistence and action orchestration.
- `plasmoid/contents/ui/NeiWizModel.js` — pure state/name helpers that can run under QtQuick Test.
- `plasmoid/contents/ui/FullRepresentation.qml` — panel, rename dialog and header status.
- `plasmoid/contents/ui/BulbRow.qml` — one bulb row, slider commit and accessible names.
- `plasmoid/contents/ui/ExecRunner.qml` — command bridge and timeout.
- `helper/wizhelper.py` — discovery, state, names and CLI contract.
- `tests/qml/` — QtQuick Test cases for QML behavior; not shipped in the plasmoid package.
- `scripts/qml-test.sh` — headless QML test runner using system PySide6.
- `scripts/default-path-check.sh` — XDG-path behavior check with a temporary applet install.

---

### Task 1: Resolve helper paths from XDG instead of `$HOME`

**Files:**
- Modify: `plasmoid/contents/ui/main.qml:19-20`
- Modify: `plasmoid/contents/config/main.xml:13-20`
- Modify: `scripts/default-path-check.sh`
- Modify: `scripts/check-plasmoid.sh:50-58`
- Modify: `README.md:25-27,81,114,190`
- Modify: `docs/superpowers/specs/2026-11-03-neiwiz-design.md:51,120-123`

**Interfaces:**
- Produces: `defaultHelperCommand` and `defaultHelperScript` computed from `StandardPaths.writableLocation(StandardPaths.GenericDataLocation)`, which respects `XDG_DATA_HOME`.
- Produces: `helperCommand` and `helperScript` configuration entries with empty defaults so QML owns path resolution.
- Produces: `scripts/default-path-check.sh` installs the applet and fake helper under a temporary `XDG_DATA_HOME`, with `HOME` pointing elsewhere.

- [ ] **Step 1: Rewrite the failing path check**

In `scripts/default-path-check.sh`, replace `REAL_DATA_HOME` with two temporary roots:

```bash
TMP_HOME="$(mktemp -d)"
TMP_DATA="$TMP_HOME/xdg-data"
mkdir -p "$TMP_DATA/neiwiz/venv/bin" "$TMP_HOME/.config" "$TMP_HOME/.cache"
ln -s "$(command -v python3)" "$TMP_DATA/neiwiz/venv/bin/python"
```

Install the applet into `TMP_DATA`, put the fake helper in `$TMP_DATA/neiwiz/wizhelper.py`, and launch with `HOME="$TMP_HOME"`, `XDG_CONFIG_HOME="$TMP_HOME/.config"`, `XDG_CACHE_HOME="$TMP_HOME/.cache"` and `XDG_DATA_HOME="$TMP_DATA"`. Keep the marker assertion that the helper receives `discover`.

- [ ] **Step 2: Run the check and watch it fail**

Run: `bash scripts/default-path-check.sh`
Expected: `FALLO: el helper no se ejecutó con discover` because `main.qml` still reads `$HOME/.local/share`.

- [ ] **Step 3: Derive the default paths in QML**

Replace the two `$HOME` constants with:

```qml
readonly property string dataHome:
    toLocalPath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))
readonly property string defaultHelperCommand:
    dataHome + "/neiwiz/venv/bin/python"
readonly property string defaultHelperScript:
    dataHome + "/neiwiz/wizhelper.py"
```

Keep `expandPath` for user-supplied custom paths.

- [ ] **Step 4: Remove the `$HOME` defaults from KConfig**

In `plasmoid/contents/config/main.xml`, leave `helperCommand` and `helperScript` entries declared but give both `<default/>`. Existing explicit user values continue to work; empty values fall back to QML.

- [ ] **Step 5: Pin the fix in the static package check**

In `scripts/check-plasmoid.sh`, fail when `main.xml` still contains `$HOME/.local/share` or when `main.qml` does not contain `StandardPaths.GenericDataLocation`.

- [ ] **Step 6: Update docs and run both checks**

Document the XDG-aware install path in `README.md` and the design spec. Run:

```bash
bash scripts/check-plasmoid.sh
bash scripts/default-path-check.sh
```

Expected: `OK: paquete del plasmoid válido` and `OK: el helper por defecto se ejecuta (discover)`.

- [ ] **Step 7: Commit**

```bash
git add plasmoid/contents/ui/main.qml plasmoid/contents/config/main.xml \
    scripts/default-path-check.sh scripts/check-plasmoid.sh README.md \
    docs/superpowers/specs/2026-11-03-neiwiz-design.md
git commit -m "fix: resolve helper paths from XDG data home"
```

---

### Task 2: Rename bulbs by MAC and add QML behavior tests

**Files:**
- Create: `scripts/qml-test.sh`
- Create: `tests/qml/tst_bulbrow.qml`
- Create: `tests/qml/tst_fullrepresentation.qml`
- Modify: `plasmoid/contents/ui/BulbRow.qml:20-22,114-123`
- Modify: `plasmoid/contents/ui/FullRepresentation.qml:17,25,27-31,260-262`
- Modify: `plasmoid/contents/ui/main.qml:150-158,572-574`
- Modify: `scripts/smoke-plasmoid.sh:26-31`
- Modify: `README.md:157-165`

**Interfaces:**
- Produces: `BulbRow.renameRequested(string mac, string currentName)`.
- Produces: `FullRepresentation.renameMac: string`; `openRenameDialog(mac: string, currentName: string)`; `renameRequested(string mac, string name)`.
- Produces: `main.renameBulb(mac: string, name: string)`.
- Produces: `bash scripts/qml-test.sh` runs `tests/qml` headlessly with `QT_QPA_PLATFORM=offscreen` and returns non-zero on failure.

- [ ] **Step 1: Add the QML test runner**

Create `scripts/qml-test.sh`:

```bash
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
```

- [ ] **Step 2: Write the failing row test**

Create `tests/qml/tst_bulbrow.qml`:

```qml
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as NeiWiz

TestCase {
    name: "BulbRow"
    id: testCase
    when: windowShown

    Component {
        id: rowComponent
        NeiWiz.BulbRow {
            rowIndex: 3
            bulbName: "Bombilla EEFF"
            mac: "aabbccddeeff"
            customName: "Despacho"
            online: true
        }
    }

    Component { id: spyComponent; SignalSpy { signalName: "renameRequested" } }

    function test_rename_button_emits_mac() {
        let row = createTemporaryObject(rowComponent, testCase)
        verify(row)
        let button = findChild(row, "renameButton")
        verify(button)
        let spy = spyComponent.createObject(testCase, {target: row})
        verify(spy.valid)
        button.clicked()
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "aabbccddeeff")
        compare(spy.signalArguments[0][1], "Despacho")
    }
}
```

Expected before implementation: FAIL at `verify(button)` because the button has no `objectName` yet.

- [ ] **Step 3: Write the failing dialog-reorder test**

Create `tests/qml/tst_fullrepresentation.qml` with a `ListModel` containing two bulbs, a `SignalSpy` for `renameRequested`, and this case:

```qml
function test_dialog_follows_mac_when_model_reorders() {
    let panel = createTemporaryObject(fullComponent, testCase)
    verify(panel)
    let dialog = findChild(panel, "renameDialog")
    let field = findChild(dialog, "renameField")
    verify(dialog)
    verify(field)
    let spy = spyComponent.createObject(testCase, {target: panel})
    verify(spy.valid)
    panel.openRenameDialog("112233445566", "Cocina")
    tryCompare(field, "text", "Cocina")
    panel.sourceModel.move(1, 0, 1)
    dialog.accept()
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "112233445566")
    compare(spy.signalArguments[0][1], "Cocina")
}
```

Define `sourceModel` as a property on the `FullRepresentation` instance so the test can move rows. Expected before implementation: `Cannot assign QString to int` at `FullRepresentation.qml`'s `renameIndex = index`.

- [ ] **Step 4: Run the QML tests and confirm both fail for the right reason**

Run: `bash scripts/qml-test.sh`
Expected: the row test fails at `verify(button)`; the dialog test reports the QString-to-int error.

- [ ] **Step 5: Change the row signal to carry MAC**

In `BulbRow.qml`:

```qml
signal renameRequested(string mac, string currentName)
```

Add `objectName: "renameButton"` to the rename `ToolButton`. Change its handler to:

```qml
onClicked: root.renameRequested(root.mac, root.customName)
```

- [ ] **Step 6: Store the MAC in the dialog**

In `FullRepresentation.qml`, replace `property int renameIndex` with `property string renameMac`, change `openRenameDialog(mac, currentName)`, and emit `root.renameRequested(root.renameMac, renameField.text)` on accept. Add `objectName: "renameDialog"` and `objectName: "renameField"` for the behavior test.

- [ ] **Step 7: Change `main.qml` to accept a MAC**

Replace `renameBulb(index, name)` with `renameBulb(mac, name)`. Drop the index bounds check and read `const key = normalizeMac(mac);`. Keep the existing optimistic update, per-MAC save versions and rollback logic. Wire `onRenameRequested: function(mac, name) { root.renameBulb(mac, name); }`.

- [ ] **Step 8: Update the smoke check and README**

Add `renameMac` to the `FullRepresentation.qml` tokens checked by `scripts/smoke-plasmoid.sh`. Add `bash scripts/qml-test.sh` to the development commands in `README.md` and mention `python3-pyside6` as a test-only requirement.

- [ ] **Step 9: Run the tests**

```bash
bash scripts/qml-test.sh
bash scripts/check-plasmoid.sh
```

Expected: all QML tests PASS and the package check PASS.

- [ ] **Step 10: Commit**

```bash
git add scripts/qml-test.sh tests/qml plasmoid/contents/ui/BulbRow.qml \
    plasmoid/contents/ui/FullRepresentation.qml plasmoid/contents/ui/main.qml \
    scripts/smoke-plasmoid.sh README.md
git commit -m "fix: rename bulbs by MAC instead of row index"
```

---

### Task 3: Refuse to overwrite a corrupt names file

**Files:**
- Modify: `helper/wizhelper.py:69-119`
- Test: `tests/test_wizhelper.py:249-326`

**Interfaces:**
- Produces: `load_names(path: Path | None = None) -> dict[str, str]` stays tolerant and returns `{}` for unreadable or invalid files.
- Produces: `set_name(mac: str, name: str, path: Path | None = None) -> dict[str, Any]` returns `{"ok": False, "error": "..."}` when the existing file is not a JSON object, without writing.

- [ ] **Step 1: Write the failing corrupt-file test**

Add to `tests/test_wizhelper.py`:

```python
@pytest.mark.parametrize("content", ["{not json", '["not", "an", "object"]'])
def test_set_name_refuses_to_overwrite_corrupt_file(helper, tmp_path, content):
    path = tmp_path / "names.json"
    path.write_text(content, encoding="utf-8")

    result = helper.set_name("AABBCCDDEEFF", "Despacho", path)

    assert result["ok"] is False
    assert "nombre" in result["error"].lower()
    assert path.read_text(encoding="utf-8") == content
```

Also add a preservation test:

```python
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
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `.venv/bin/pytest tests/test_wizhelper.py::test_set_name_refuses_to_overwrite_corrupt_file -v`
Expected: FAIL because the corrupt file is treated as `{}` and replaced with the new name.

- [ ] **Step 3: Split tolerant reads from strict writes**

Add `_read_names_file(source: Path) -> dict[str, str]` that raises `ValueError` when the top-level JSON value is not an object, then applies the existing MAC/name filtering. Make `load_names` call it and catch `OSError`/`ValueError`, returning `{}`.

In `set_name`, after taking the lock:

```python
try:
    names = _read_names_file(target)
except FileNotFoundError:
    names = {}
except (OSError, ValueError) as exc:
    return {"ok": False, "error": f"No se pudo leer la lista de nombres: {exc}"}
```

Then apply the rename and `save_names` as today. Do not catch the strict error inside `load_names`.

- [ ] **Step 4: Run the helper tests**

Run: `.venv/bin/pytest tests/test_wizhelper.py -q`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add helper/wizhelper.py tests/test_wizhelper.py
git commit -m "fix: keep corrupt bulb name files untouched"
```

---

### Task 4: Preserve busy rows during refresh and clear stale errors

**Files:**
- Create: `plasmoid/contents/ui/NeiWizModel.js`
- Create: `tests/qml/tst_model.qml`
- Modify: `plasmoid/contents/ui/main.qml:210-216,318-340,448-511`

**Interfaces:**
- Produces: `NeiWizModel.clampBrightness(value) -> int` in the 1..100 range, defaulting to 100 for non-finite values.
- Produces: `NeiWizModel.applyState(row, state) -> object | null`; returns `null` when `row.busy === true`, otherwise `{online: bool, on: bool, brightness: int, mac: string}`.
- Consumes: `bulbsModel` rows with `busy`, `online`, `on`, `brightness` and `mac`.

- [ ] **Step 1: Write the failing model test**

Create `tests/qml/tst_model.qml`:

```qml
import QtQuick
import QtTest
import "../../plasmoid/contents/ui/NeiWizModel.js" as NeiWizModel

TestCase {
    name: "NeiWizModel"

    function test_busy_row_is_untouched() {
        compare(
            NeiWizModel.applyState(
                {busy: true},
                {online: true, on: true, brightness: 80, mac: "aabbccddeeff"}
            ),
            null
        )
    }

    function test_state_is_normalized() {
        let update = NeiWizModel.applyState(
            {busy: false},
            {online: true, on: true, brightness: 150, mac: "AABBCCDDEEFF"}
        )
        compare(update.online, true)
        compare(update.on, true)
        compare(update.brightness, 100)
        compare(update.mac, "AABBCCDDEEFF")
    }

    function test_invalid_brightness_defaults_to_100() {
        compare(NeiWizModel.clampBrightness("nope"), 100)
        compare(NeiWizModel.clampBrightness(0), 1)
        compare(NeiWizModel.clampBrightness(999), 100)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/qml-test.sh`
Expected: FAIL because `NeiWizModel.js` does not exist.

- [ ] **Step 3: Implement the pure model helpers**

Create `plasmoid/contents/ui/NeiWizModel.js`:

```javascript
.pragma library

function clampBrightness(value) {
    const number = Math.round(Number(value));
    if (!isFinite(number)) {
        return 100;
    }
    return Math.max(1, Math.min(100, number));
}

function applyState(row, state) {
    if (!row || !state || row.busy) {
        return null;
    }
    return {
        online: state.online === true,
        on: state.on === true,
        brightness: clampBrightness(state.brightness),
        mac: typeof state.mac === "string" ? state.mac : "",
    };
}
```

- [ ] **Step 4: Use the module in `main.qml`**

Add `import "NeiWizModel.js" as NeiWizModel`. Delete the local `clampBrightness` function and replace all calls with `NeiWizModel.clampBrightness`. Rewrite the state loop in `applyStates` so it reads the current row and skips when the helper returns `null`:

```qml
const item = bulbsModel.get(index);
const update = NeiWizModel.applyState(item, state);
if (!update) {
    continue;
}
bulbsModel.setProperty(index, "online", update.online);
bulbsModel.setProperty(index, "on", update.on);
bulbsModel.setProperty(index, "brightness", update.brightness);
if (update.mac.length > 0) {
    bulbsModel.setProperty(index, "mac", update.mac);
    bulbsModel.setProperty(index, "customName", customNameFor(update.mac));
    bulbsModel.setProperty(index, "name", bulbName(update.mac, state.ip));
}
```

Do not set `busy` to false in `applyStates`; the action callback owns that flag.

- [ ] **Step 5: Clear the stale error banner on row actions**

At the start of `togglePower` and `setBrightness`, after the bounds/availability checks, set `lastError = ""`. Do not clear it before the checks that return early.

- [ ] **Step 6: Run the QML and helper tests**

```bash
bash scripts/qml-test.sh
.venv/bin/pytest -q
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add plasmoid/contents/ui/NeiWizModel.js plasmoid/contents/ui/main.qml tests/qml/tst_model.qml
git commit -m "fix: keep in-flight bulb actions during state refresh"
```

---

### Task 5: Replace the 8 s command cap with a 30 s safety timeout

**Files:**
- Modify: `plasmoid/contents/ui/ExecRunner.qml:8-15,46-52`
- Create: `tests/qml/tst_execrunner.qml`

**Interfaces:**
- Produces: `ExecRunner.timeoutMs: int` with default `30000`; the timer uses it.
- Produces: callback contract unchanged: `(stdout: string, stderr: string, exitCode: int)`.

- [ ] **Step 1: Write the failing timeout test**

Create `tests/qml/tst_execrunner.qml`:

```qml
import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as NeiWiz

TestCase {
    name: "ExecRunner"
    id: testCase
    when: windowShown

    Component { id: runnerComponent; NeiWiz.ExecRunner { timeoutMs: 100 } }
    Component { id: defaultRunner; NeiWiz.ExecRunner {} }

    function test_slow_command_times_out() {
        let runner = createTemporaryObject(runnerComponent, testCase)
        verify(runner)
        let called = false
        let exitCode = 0
        let stderr = ""
        runner.run("sleep 1", function(stdout, error, code) {
            called = true
            exitCode = code
            stderr = error
        })
        tryVerify(function() { return called }, 2000)
        compare(exitCode, -1)
        compare(stderr, "Tiempo de espera agotado")
    }

    function test_default_timeout_is_30_seconds() {
        let runner = createTemporaryObject(defaultRunner, testCase)
        verify(runner)
        compare(runner.timeoutMs, 30000)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/qml-test.sh`
Expected: FAIL because `ExecRunner` has no `timeoutMs` property.

- [ ] **Step 3: Add the property and use it**

In `ExecRunner.qml`, add `property int timeoutMs: 30000`. After creating the timer and before `timer.start()`, set `timer.interval = runner.timeoutMs;`. Remove the hard-coded `interval: 8000` from `timerComponent`.

The helper enforces its own 2.5 s bulb timeout and 4 s discovery timeout; 30 s is only a last-resort guard against a hung process.

- [ ] **Step 4: Run the QML tests**

Run: `bash scripts/qml-test.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add plasmoid/contents/ui/ExecRunner.qml tests/qml/tst_execrunner.qml
git commit -m "fix: give discovery a realistic command timeout"
```

---

### Task 6: Commit slider changes from keyboard and wheel, and label the slider

**Files:**
- Modify: `plasmoid/contents/ui/BulbRow.qml:75-103`
- Modify: `tests/qml/tst_bulbrow.qml`

**Interfaces:**
- Produces: `BulbRow` emits `brightnessCommitted(int index, int value)` whenever the slider's `moved()` signal fires outside a drag, and once when a drag is released.
- Produces: slider `objectName: "brightnessSlider"` and `Accessible.name: "Brillo de " + root.bulbName`.

- [ ] **Step 1: Add the failing slider tests**

Append to `tests/qml/tst_bulbrow.qml`:

```qml
Component { id: brightnessSpyComponent; SignalSpy { signalName: "brightnessCommitted" } }

function test_moved_commits_without_press() {
    let row = createTemporaryObject(rowComponent, testCase)
    verify(row)
    let slider = findChild(row, "brightnessSlider")
    verify(slider)
    let spy = brightnessSpyComponent.createObject(testCase, {target: row})
    verify(spy.valid)
    slider.value = 51
    slider.moved()
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], 3)
    compare(spy.signalArguments[0][1], 51)
}

function test_slider_has_accessible_name() {
    let row = createTemporaryObject(rowComponent, testCase)
    let slider = findChild(row, "brightnessSlider")
    verify(slider)
    compare(slider.Accessible.name, "Brillo de Bombilla EEFF")
}
```

The `moved()` signal is the same path Qt emits for keyboard and wheel changes, so this pins the missing handler without brittle focus simulation.

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/qml-test.sh`
Expected: FAIL because `findChild(row, "brightnessSlider")` returns null.

- [ ] **Step 3: Add `objectName`, accessibility and a single commit function**

In `BulbRow.qml`:

```qml
function commitBrightness() {
    const committed = Math.round(brightnessSlider.value);
    if (committed !== root.brightness) {
        root.brightnessCommitted(root.rowIndex, committed);
    }
}
```

Add to the slider:

```qml
objectName: "brightnessSlider"
Accessible.name: "Brillo de " + root.bulbName
onMoved: if (!brightnessSlider.pressed) commitBrightness()
onPressedChanged: if (!brightnessSlider.pressed) commitBrightness()
```

Remove the old `onPressedChanged` body. Keep the existing `Binding` with `when: !brightnessSlider.pressed` so dragging stays visual until release.

- [ ] **Step 4: Run the QML tests**

Run: `bash scripts/qml-test.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add plasmoid/contents/ui/BulbRow.qml tests/qml/tst_bulbrow.qml
git commit -m "fix: commit slider changes from keyboard and wheel"
```

---

### Task 7: Try every local broadcast interface

**Files:**
- Modify: `helper/wizhelper.py:163-189,254-292`
- Test: `tests/test_wizhelper.py:95-156`

**Interfaces:**
- Produces: `local_broadcasts() -> list[str]`, unique broadcast addresses in `ip addr` order.
- Changes: `discover_bulbs() -> list[dict[str, Any]]` no longer accepts a `broadcast` argument.
- Produces: discovery order `255.255.255.255`, then each local broadcast, stopping at the first address that returns bulbs.

- [ ] **Step 1: Rewrite the broadcast tests**

Replace the two `local_broadcast` tests with:

```python
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
```

Update the discovery test so the fake `find_wizlights` rejects both the global and the first local broadcast, and returns the bulb on the second local broadcast:

```python
async def fake_find(wait_time, broadcast_address):
    addresses.append(broadcast_address)
    if broadcast_address in ("255.255.255.255", "192.168.1.255"):
        return []
    return [fake_bulb]

monkeypatch.setattr(helper, "local_broadcasts", lambda: ["192.168.1.255", "10.0.0.255"])
...
assert addresses == ["255.255.255.255", "192.168.1.255", "10.0.0.255"]
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `.venv/bin/pytest tests/test_wizhelper.py -q`
Expected: FAIL because `local_broadcasts` does not exist and `discover_bulbs` still stops after the first local address.

- [ ] **Step 3: Implement `local_broadcasts`**

Reuse the existing `ip -4 -o addr show scope global` call. Iterate all matching lines, build `IPv4Interface(f"{address}/{prefix}")`, append `str(interface.network.broadcast_address)` only if not already present, and return the list. Remove the unreachable `returncode` check because `check=True` already raises.

- [ ] **Step 4: Rewrite discovery**

Build the candidate list as `[GLOBAL_BROADCAST] + local_broadcasts()`, deduplicated. Try each address with `_find_on`; break on the first non-empty result. Remove the `broadcast` parameter and the special-case branch. Keep the existing MAC/IP merge and `query_many` call.

- [ ] **Step 5: Run the tests**

Run: `.venv/bin/pytest tests/test_wizhelper.py -q`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add helper/wizhelper.py tests/test_wizhelper.py
git commit -m "fix: try every local broadcast interface"
```

---

### Task 8: Remove CLI workarounds and accept one bad saved IP

**Files:**
- Modify: `helper/wizhelper.py:10-19,122-139,324-347,359-364`
- Modify: `plasmoid/contents/ui/main.qml:181-184`
- Modify: `tests/test_wizhelper.py:314-325`
- Modify: `scripts/smoke-plasmoid.sh:9-14`

**Interfaces:**
- Produces: `set-name` accepts `--name=<value>`; the QML caller always uses that form.
- Changes: `state` ignores invalid IPs, queries the valid ones, and fails only when no valid IP remains.
- Removes: `_fix_name_option`, the `sys` import and the `--name` separate-value workaround.

- [ ] **Step 1: Update the dash-name test to the equals form**

Replace `test_main_set_name_accepts_name_starting_with_dash` with:

```python
def test_main_set_name_accepts_equals_form_with_dash(helper, monkeypatch, capsys, tmp_path):
    path = tmp_path / "names.json"
    monkeypatch.setattr(helper, "names_path", lambda: path)

    code = helper.main(["set-name", "--mac", "AABBCCDDEEFF", "--name=-luz"])

    payload = json.loads(capsys.readouterr().out)
    assert code == 0
    assert payload["ok"] is True
    assert helper.load_names(path) == {"aabbccddeeff": "-luz"}
```

Add the mixed-IP test:

```python
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
```

- [ ] **Step 2: Run them and watch the new state test fail**

Run: `.venv/bin/pytest tests/test_wizhelper.py -q`
Expected: `test_main_state_skips_invalid_saved_ips` FAILS because any invalid IP rejects the whole call.

- [ ] **Step 3: Filter invalid state IPs**

In the `state` branch, normalize each `--ip` with `safe_ip`, keep the valid entries in order, deduplicate, and return the existing `{"ok": False, "error": "dirección IP no válida"}` only when the list is empty. Pass the filtered list to `query_many`.

- [ ] **Step 4: Remove `_fix_name_option` and use the equals form in QML**

Delete `_fix_name_option`, remove `import sys`, and call `parser.parse_args(argv)` directly. Change `main.qml` to build `--name=` plus `shellQuote(trimmed)` so the shell produces one `--name=<value>` argument.

Add `grep -F -- '--name=' "$main_qml"` to `scripts/smoke-plasmoid.sh` and remove any check that depends on `_fix_name_option`.

- [ ] **Step 5: Run the helper tests**

Run: `.venv/bin/pytest tests/test_wizhelper.py -q`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add helper/wizhelper.py plasmoid/contents/ui/main.qml tests/test_wizhelper.py \
    scripts/smoke-plasmoid.sh
git commit -m "refactor: pass set-name values in equals form"
```

---

### Task 9: Fix the first-query header and delete dead code

**Files:**
- Modify: `plasmoid/contents/ui/FullRepresentation.qml:33-34,52-70`
- Modify: `plasmoid/contents/ui/main.qml:12-17`
- Modify: `tests/qml/tst_fullrepresentation.qml`
- Delete: `docs/superpowers/plans/2026-11-03-neiwiz.md`
- Modify: `README.md:103-116,142-147`

**Interfaces:**
- Produces: header status text `"Actualizando…"` while `root.busy` is true, before the `"Sin conexión"` branch.
- Produces: `statusLabel` object name for the QML test.
- Removes: the unused `inPanel` property and the duplicate `Layout.minimumWidth`/`Layout.minimumHeight` values in `FullRepresentation.qml`.

- [ ] **Step 1: Add the failing header test**

Append to `tests/qml/tst_fullrepresentation.qml`:

```qml
function test_status_shows_updating_while_busy() {
    let panel = createTemporaryObject(fullComponent, testCase)
    let label = findChild(panel, "statusLabel")
    verify(label)
    panel.busy = true
    panel.allOffline = true
    compare(label.text, "Actualizando…")
    panel.busy = false
    compare(label.text, "Sin conexión")
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/qml-test.sh`
Expected: FAIL because `statusLabel` does not exist.

- [ ] **Step 3: Add the busy status branch**

On the header status `Label`, add `objectName: "statusLabel"` and make the text start with:

```qml
if (root.busy) {
    return "Actualizando…";
}
```

Keep the existing no-bulbs, all-offline, any-on and all-off branches after it.

- [ ] **Step 4: Delete dead code**

Remove `inPanel` from `main.qml`. Remove the `Layout.minimumWidth` and `Layout.minimumHeight` lines from `FullRepresentation.qml`; the instance in `main.qml` already sets them.

Delete `docs/superpowers/plans/2026-11-03-neiwiz.md`; the completed plan is preserved by git history and no longer describes the shipped code.

- [ ] **Step 5: Document the corrupt-names recovery**

In `README.md`, add a troubleshooting entry: if `~/.config/neiwiz/bulb-names.json` is corrupt, rename refuses to touch it; back it up, delete or repair it, then retry.

- [ ] **Step 6: Run all checks**

```bash
.venv/bin/pytest -q
bash scripts/check-plasmoid.sh
bash scripts/qml-test.sh
git diff --check
```

Expected: all tests PASS, package check PASS, QML tests PASS, no whitespace errors.

- [ ] **Step 7: Commit**

```bash
git add plasmoid/contents/ui/FullRepresentation.qml plasmoid/contents/ui/main.qml \
    tests/qml/tst_fullrepresentation.qml README.md
git add -u docs/superpowers/plans/2026-11-03-neiwiz.md
git commit -m "chore: remove dead UI code and stale plan"
```

---

## Verification Checklist

- [ ] `.venv/bin/pytest -q` passes.
- [ ] `bash scripts/check-plasmoid.sh` prints `OK: paquete del plasmoid válido`.
- [ ] `bash scripts/qml-test.sh` passes headlessly.
- [ ] `bash scripts/default-path-check.sh` passes with `HOME` and `XDG_DATA_HOME` in different directories.
- [ ] This reports no syntax errors:

  ```bash
  for script in install.sh uninstall.sh scripts/*.sh; do
      bash -n "$script"
  done
  ```
- [ ] `git diff --check` is clean.
- [ ] No test upgraded or modified the live applet.
