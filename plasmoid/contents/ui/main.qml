import QtQuick
import QtQuick.Layouts
import QtCore

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "NeiWizModel.js" as NeiWizModel

PlasmoidItem {
    id: root

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)

    readonly property string dataHome:
        toLocalPath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))
    readonly property string defaultHelperCommand:
        dataHome + "/neiwiz/venv/bin/python"
    readonly property string defaultHelperScript:
        dataHome + "/neiwiz/wizhelper.py"

    property ListModel bulbsModel: ListModel {}
    property var customNames: ({})
    property var changedNameKeys: ({})
    property var nameSaveVersions: ({})
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

    function normalizeMac(mac) {
        return String(mac || "").toUpperCase().replace(/[^0-9A-F]/g, "");
    }

    function customNameFor(mac) {
        const clean = normalizeMac(mac);
        if (clean.length === 0 || !customNames || typeof customNames !== "object") {
            return "";
        }
        const value = customNames[clean];
        return typeof value === "string" ? value : "";
    }

    function bulbName(mac, ip) {
        const custom = customNameFor(mac);
        if (custom.length > 0) {
            return custom;
        }
        const clean = normalizeMac(mac);
        if (clean.length >= 4) {
            return "Bombilla " + clean.slice(-4);
        }
        const octets = String(ip || "").split(".");
        return "Bombilla " + (octets.length > 0 ? octets[octets.length - 1] : "WiZ");
    }

    function loadCustomNames() {
        execRunner.run(helperCommandLine("names"), function(stdout, stderr, exitCode) {
            const payload = parsePayload(stdout, stderr, exitCode);
            if (!payload) {
                return;
            }

            let names = {};
            const parsed = payload.names;
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                for (const key in parsed) {
                    if (typeof parsed[key] !== "string") {
                        continue;
                    }
                    const clean = normalizeMac(key);
                    const name = parsed[key].trim();
                    if (clean.length > 0 && name.length > 0) {
                        names[clean] = name;
                    }
                }
            }
            for (const key in changedNameKeys) {
                if (Object.prototype.hasOwnProperty.call(customNames, key)) {
                    names[key] = customNames[key];
                } else {
                    delete names[key];
                }
            }
            customNames = names;
            updateModelNames();
        });
    }

    function updateModelNames() {
        for (let i = 0; i < bulbsModel.count; ++i) {
            const item = bulbsModel.get(i);
            bulbsModel.setProperty(i, "customName", customNameFor(item.mac));
            bulbsModel.setProperty(i, "name", bulbName(item.mac, item.ip));
        }
    }

    function renameBulb(mac, name) {
        const key = normalizeMac(mac);
        if (key.length === 0) {
            return;
        }

        const previous = customNames;
        const hadPrevious = Object.prototype.hasOwnProperty.call(previous, key);
        const previousName = hadPrevious ? previous[key] : "";
        const version = (nameSaveVersions[key] || 0) + 1;
        const next = {};
        for (const existing in customNames) {
            next[existing] = customNames[existing];
        }
        const trimmed = String(name || "").trim();
        if (trimmed.length > 0) {
            next[key] = trimmed;
        } else {
            delete next[key];
        }

        nameSaveVersions[key] = version;
        changedNameKeys[key] = true;
        customNames = next;
        updateModelNames();
        lastError = "";

        const command = helperCommandLine(
            "set-name",
            "--mac " + shellQuote(key) + " --name " + shellQuote(trimmed)
        );
        execRunner.run(command, function(stdout, stderr, exitCode) {
            const previousError = lastError;
            const payload = parsePayload(stdout, stderr, exitCode);
            if (nameSaveVersions[key] !== version) {
                lastError = previousError;
                return;
            }
            if (!payload) {
                const reverted = {};
                for (const existing in customNames) {
                    if (existing !== key) {
                        reverted[existing] = customNames[existing];
                    }
                }
                if (hadPrevious) {
                    reverted[key] = previousName;
                }
                customNames = reverted;
                updateModelNames();
                delete changedNameKeys[key];
                loadCustomNames();
            }
        });
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
                customName: customNameFor(entry.mac),
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
            const previous = [];
            for (let i = 0; i < bulbsModel.count; ++i) {
                const item = bulbsModel.get(i);
                previous.push({ ip: item.ip, mac: item.mac || "" });
            }

            const discoveredMacs = {};
            const discoveredIps = {};
            for (let i = 0; i < bulbs.length; ++i) {
                const bulb = bulbs[i];
                if (!bulb || typeof bulb.ip !== "string") {
                    continue;
                }
                const clean = normalizeMac(bulb.mac);
                if (clean.length > 0) {
                    discoveredMacs[clean] = true;
                }
                discoveredIps[bulb.ip] = true;
            }

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
                    customName: customNameFor(bulb.mac),
                    online: bulb.online === true,
                    on: bulb.on === true,
                    brightness: NeiWizModel.clampBrightness(bulb.brightness),
                    busy: false,
                });
            }

            for (let i = 0; i < previous.length; ++i) {
                const entry = previous[i];
                const clean = normalizeMac(entry.mac);
                if ((clean.length > 0 && discoveredMacs[clean]) || discoveredIps[entry.ip]) {
                    continue;
                }
                bulbsModel.append({
                    ip: entry.ip,
                    mac: entry.mac,
                    name: bulbName(entry.mac, entry.ip),
                    customName: customNameFor(entry.mac),
                    online: false,
                    on: false,
                    brightness: 100,
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
        lastError = "";

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
        lastError = "";

        const ip = item.ip;
        const previous = item.brightness;
        const value = NeiWizModel.clampBrightness(pct);
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
        loadCustomNames();
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
        onRenameRequested: function(mac, name) {
            root.renameBulb(mac, name);
        }
    }
}
