import QtQuick

import org.kde.plasma.plasma5support as Plasma5Support

QtObject {
    id: runner

    property int nextId: 0
    property var pending: ({})
    property int timeoutMs: 30000

    function run(command, callback) {
        const id = ++nextId;
        const sourceName = command + " # neiwiz-" + id;
        const source = sourceComponent.createObject(runner);
        const timer = timerComponent.createObject(runner);

        if (!source || !timer) {
            if (source) {
                source.destroy();
            }
            if (timer) {
                timer.destroy();
            }
            callback("", "Could not start the process", 1);
            return "";
        }

        pending[sourceName] = {
            callback: callback,
            source: source,
            timer: timer,
        };

        source.newData.connect(function(name, data) {
            if (data["exit code"] === undefined) {
                return;
            }
            runner.finish(
                name,
                String(data["stdout"] || ""),
                String(data["stderr"] || ""),
                Number(data["exit code"])
            );
        });

        timer.triggered.connect(function() {
            runner.finish(sourceName, "", "Tiempo de espera agotado", -1);
        });

        source.connectedSources = [sourceName];
        timer.interval = runner.timeoutMs;
        timer.start();
        return sourceName;
    }

    function finish(sourceName, stdout, stderr, exitCode) {
        const entry = pending[sourceName];
        if (!entry) {
            return;
        }
        delete pending[sourceName];

        if (entry.timer) {
            entry.timer.stop();
            entry.timer.destroy();
        }
        if (entry.source) {
            entry.source.connectedSources = [];
            entry.source.destroy();
        }
        entry.callback(stdout, stderr, exitCode);
    }

    property Component sourceComponent: Component {
        Plasma5Support.DataSource {
            engine: "executable"
        }
    }

    property Component timerComponent: Component {
        Timer {
            repeat: false
        }
    }
}
