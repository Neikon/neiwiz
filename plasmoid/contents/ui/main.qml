import QtQuick
import QtQuick.Layouts
import QtCore

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)

    readonly property string defaultHelperCommand: "$HOME/.local/share/neiwiz/venv/bin/python"
    readonly property string defaultHelperScript: "$HOME/.local/share/neiwiz/wizhelper.py"

    property ListModel bulbsModel: ListModel {}
    property bool busy: false
    property bool ready: false
    property bool autoDiscoverTried: false
    property int onCount: 0
    readonly property bool anyOn: onCount > 0
    property bool allOffline: false
    property string lastError: ""

    Plasmoid.icon: root.anyOn ? "flashlight-on-symbolic" : "flashlight-off-symbolic"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: "NeiWiz"
    toolTipSubText: root.bulbsModel.count === 0
        ? "Abre el panel para buscar bombillas"
        : (root.anyOn
            ? root.onCount + (root.onCount === 1 ? " encendida" : " encendidas")
            : "Todas apagadas")

    function toLocalPath(value) {
        const text = String(value || "");
        if (text.indexOf("file://") !== 0) {
            return text;
        }
        try {
            return decodeURIComponent(text.substring(7));
        } catch (error) {
            return text.substring(7);
        }
    }

    function expandPath(value) {
        const path = toLocalPath(value);
        const home = toLocalPath(StandardPaths.writableLocation(StandardPaths.HomeLocation));
        if (path === "~") {
            return home;
        }
        if (path.indexOf("~/") === 0) {
            return home + path.substring(1);
        }
        if (path.indexOf("$HOME") === 0) {
            return home + path.substring(5);
        }
        return path;
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function helperCommandLine(subcommand, args) {
        const command = Plasmoid.configuration.helperCommand || defaultHelperCommand;
        const script = Plasmoid.configuration.helperScript || defaultHelperScript;
        return shellQuote(expandPath(command))
            + " " + shellQuote(expandPath(script))
            + " " + subcommand
            + (args ? " " + args : "");
    }

    function bulbName(mac, ip) {
        const clean = String(mac || "").toUpperCase().replace(/[^0-9A-F]/g, "");
        if (clean.length >= 4) {
            return "Bombilla " + clean.slice(-4);
        }
        const octets = String(ip || "").split(".");
        return "Bombilla " + (octets.length > 0 ? octets[octets.length - 1] : "WiZ");
    }

    function clampBrightness(value) {
        const number = Math.round(Number(value));
        if (!isFinite(number)) {
            return 100;
        }
        return Math.max(1, Math.min(100, number));
    }

    function loadKnownBulbs() {
        let entries = [];
        try {
            const parsed = JSON.parse(Plasmoid.configuration.knownBulbs || "[]");
            if (Array.isArray(parsed)) {
                entries = parsed;
            }
        } catch (error) {
            lastError = "La lista guardada de bombillas no es válida.";
        }

        bulbsModel.clear();
        for (let i = 0; i < entries.length; ++i) {
            const entry = entries[i];
            if (!entry || typeof entry.ip !== "string" || entry.ip.length === 0) {
                continue;
            }
            bulbsModel.append({
                ip: entry.ip,
                mac: typeof entry.mac === "string" ? entry.mac : "",
                name: bulbName(entry.mac, entry.ip),
                online: false,
                on: false,
                brightness: 100,
                busy: false,
            });
        }
        recompute();
    }

    function saveKnownBulbs() {
        const entries = [];
        for (let i = 0; i < bulbsModel.count; ++i) {
            const item = bulbsModel.get(i);
            entries.push({ ip: item.ip, mac: item.mac || "" });
        }
        Plasmoid.configuration.knownBulbs = JSON.stringify(entries);
    }

    function indexOfIp(ip) {
        for (let i = 0; i < bulbsModel.count; ++i) {
            if (bulbsModel.get(i).ip === ip) {
                return i;
            }
        }
        return -1;
    }

    function recompute() {
        let count = 0;
        let onlineCount = 0;
        for (let i = 0; i < bulbsModel.count; ++i) {
            const item = bulbsModel.get(i);
            if (item.online) {
                onlineCount += 1;
                if (item.on) {
                    count += 1;
                }
            }
        }
        onCount = count;
        allOffline = bulbsModel.count > 0 && onlineCount === 0;
    }

    function parsePayload(stdout, stderr, exitCode) {
        if (exitCode === 127) {
            lastError = "Falta el motor Python de NeiWiz. Ejecuta install.sh.";
            return null;
        }
        if (exitCode !== 0) {
            const message = String(stderr || "").trim();
            lastError = message.length > 0
                ? message.split("\n").pop()
                : "El helper terminó con un error.";
            return null;
        }

        const text = String(stdout || "").trim();
        if (text.length === 0) {
            lastError = "El helper no devolvió ninguna respuesta.";
            return null;
        }

        try {
            const payload = JSON.parse(text);
            if (!payload || typeof payload !== "object") {
                throw new Error("respuesta vacía");
            }
            if (payload.ok !== true) {
                lastError = String(payload.error || "Error desconocido del helper.");
                return null;
            }
            return payload;
        } catch (error) {
            lastError = "La respuesta del helper no es JSON válido.";
            return null;
        }
    }

    function applyStates(bulbs) {
        const states = Array.isArray(bulbs) ? bulbs : [];
        for (let i = 0; i < states.length; ++i) {
            const state = states[i];
            if (!state) {
                continue;
            }
            const index = indexOfIp(state.ip);
            if (index < 0) {
                continue;
            }
            bulbsModel.setProperty(index, "online", state.online === true);
            bulbsModel.setProperty(index, "on", state.on === true);
            bulbsModel.setProperty(index, "brightness", clampBrightness(state.brightness));
            if (typeof state.mac === "string" && state.mac.length > 0) {
                bulbsModel.setProperty(index, "mac", state.mac);
                bulbsModel.setProperty(index, "name", bulbName(state.mac, state.ip));
            }
            bulbsModel.setProperty(index, "busy", false);
        }
        recompute();
    }

    function refreshState() {
        if (busy) {
            return;
        }
        if (bulbsModel.count === 0) {
            discover();
            return;
        }

        const ipArguments = [];
        for (let i = 0; i < bulbsModel.count; ++i) {
            ipArguments.push("--ip " + shellQuote(bulbsModel.get(i).ip));
        }

        busy = true;
        lastError = "";
        execRunner.run(helperCommandLine("state", ipArguments.join(" ")), function(stdout, stderr, exitCode) {
            busy = false;
            const payload = parsePayload(stdout, stderr, exitCode);
            if (!payload) {
                return;
            }
            applyStates(payload.bulbs || []);
            if (allOffline && !autoDiscoverTried) {
                autoDiscoverTried = true;
                discover();
            }
        });
    }

    function discover() {
        if (busy) {
            return;
        }

        busy = true;
        lastError = "";
        execRunner.run(helperCommandLine("discover"), function(stdout, stderr, exitCode) {
            busy = false;
            const payload = parsePayload(stdout, stderr, exitCode);
            if (!payload) {
                return;
            }

            const bulbs = Array.isArray(payload.bulbs) ? payload.bulbs : [];
            bulbsModel.clear();
            for (let i = 0; i < bulbs.length; ++i) {
                const bulb = bulbs[i];
                if (!bulb || typeof bulb.ip !== "string") {
                    continue;
                }
                bulbsModel.append({
                    ip: bulb.ip,
                    mac: typeof bulb.mac === "string" ? bulb.mac : "",
                    name: bulbName(bulb.mac, bulb.ip),
                    online: bulb.online === true,
                    on: bulb.on === true,
                    brightness: clampBrightness(bulb.brightness),
                    busy: false,
                });
            }
            saveKnownBulbs();
            recompute();
        });
    }

    function togglePower(index, on) {
        if (index < 0 || index >= bulbsModel.count) {
            return;
        }
        const item = bulbsModel.get(index);
        if (item.busy) {
            return;
        }

        const ip = item.ip;
        const previous = item.on;
        bulbsModel.setProperty(index, "busy", true);
        bulbsModel.setProperty(index, "on", on);
        recompute();

        const command = helperCommandLine(
            "set",
            "--ip " + shellQuote(ip) + (on ? " --on" : " --off")
        );
        execRunner.run(command, function(stdout, stderr, exitCode) {
            const payload = parsePayload(stdout, stderr, exitCode);
            const current = indexOfIp(ip);
            if (current < 0) {
                return;
            }
            if (!payload) {
                bulbsModel.setProperty(current, "on", previous);
            }
            bulbsModel.setProperty(current, "busy", false);
            recompute();
        });
    }

    function setBrightness(index, pct) {
        if (index < 0 || index >= bulbsModel.count) {
            return;
        }
        const item = bulbsModel.get(index);
        if (item.busy || !item.online || !item.on) {
            return;
        }

        const ip = item.ip;
        const previous = item.brightness;
        const value = clampBrightness(pct);
        bulbsModel.setProperty(index, "brightness", value);
        bulbsModel.setProperty(index, "busy", true);

        const command = helperCommandLine(
            "set",
            "--ip " + shellQuote(ip) + " --brightness " + value
        );
        execRunner.run(command, function(stdout, stderr, exitCode) {
            const payload = parsePayload(stdout, stderr, exitCode);
            const current = indexOfIp(ip);
            if (current < 0) {
                return;
            }
            if (!payload) {
                bulbsModel.setProperty(current, "brightness", previous);
            }
            bulbsModel.setProperty(current, "busy", false);
        });
    }

    onExpandedChanged: function(expanded) {
        if (expanded && ready) {
            autoDiscoverTried = false;
            refreshState();
        }
    }

    Component.onCompleted: {
        loadKnownBulbs();
        ready = true;
        if (expanded) {
            autoDiscoverTried = false;
            refreshState();
        }
    }

    ExecRunner {
        id: execRunner
    }

    compactRepresentation: MouseArea {
        id: compact

        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small
        hoverEnabled: true

        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: compact.containsMouse
        }
    }

    fullRepresentation: FullRepresentation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

        bulbsModel: root.bulbsModel
        busy: root.busy
        lastError: root.lastError
        anyOn: root.anyOn
        onCount: root.onCount
        allOffline: root.allOffline

        onRefreshRequested: {
            root.autoDiscoverTried = false;
            root.refreshState();
        }
        onDiscoverRequested: root.discover()
        onPowerToggled: function(index, on) {
            root.togglePower(index, on);
        }
        onBrightnessChanged: function(index, value) {
            root.setBrightness(index, value);
        }
    }
}
