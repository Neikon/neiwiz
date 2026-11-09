import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.Representation {
    id: root

    property ListModel bulbsModel
    property bool busy: false
    property string lastError: ""
    property bool anyOn: false
    property int onCount: 0
    property bool allOffline: false
    property string renameMac: ""

    readonly property bool helperMissing: lastError.indexOf("engine is missing") >= 0

    signal refreshRequested()
    signal discoverRequested()
    signal powerToggled(int index, bool on)
    signal brightnessChanged(int index, int value)
    signal renameRequested(string mac, string name)

    function openRenameDialog(mac, currentName) {
        renameMac = mac;
        renameField.text = String(currentName || "");
        renameDialog.open();
    }

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: "NeiWiz"
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    objectName: "statusLabel"
                    Layout.fillWidth: true
                    text: {
                        if (root.busy) {
                            return "Updating…";
                        }
                        if (root.bulbsModel.count === 0) {
                            return "No bulbs";
                        }
                        if (root.allOffline) {
                            return "Offline";
                        }
                        if (root.anyOn) {
                            return root.onCount + " on";
                        }
                        return "All off";
                    }
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents3.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                visible: root.busy
                running: visible
            }

            PlasmaComponents3.ToolButton {
                id: refreshButton

                icon.name: "view-refresh-symbolic"
                text: "Refresh state"
                display: PlasmaComponents3.AbstractButton.IconOnly
                enabled: !root.busy
                onClicked: root.refreshRequested()

                PlasmaComponents3.ToolTip {
                    text: "Refresh state"
                    visible: refreshButton.hovered
                }
            }

            PlasmaComponents3.ToolButton {
                id: searchButton

                icon.name: "search-symbolic"
                text: "Discover bulbs"
                display: PlasmaComponents3.AbstractButton.IconOnly
                enabled: !root.busy
                onClicked: root.discoverRequested()

                PlasmaComponents3.ToolTip {
                    text: "Discover bulbs"
                    visible: searchButton.hovered
                }
            }
        }
    }

    contentItem: Item {
        id: content

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                visible: root.lastError.length > 0 && root.bulbsModel.count > 0
                implicitHeight: bannerLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.smallSpacing
                color: Qt.rgba(
                    Kirigami.Theme.negativeTextColor.r,
                    Kirigami.Theme.negativeTextColor.g,
                    Kirigami.Theme.negativeTextColor.b,
                    0.15
                )

                RowLayout {
                    id: bannerLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: "dialog-warning-symbolic"
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.lastError
                        wrapMode: Text.Wrap
                    }
                }
            }

            ListView {
                id: bulbList

                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.bulbsModel.count > 0
                clip: true
                model: root.bulbsModel
                spacing: Kirigami.Units.smallSpacing
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing

                PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar {}

                delegate: BulbRow {
                    rowIndex: index
                    bulbName: model.name
                    ip: model.ip
                    mac: model.mac
                    customName: model.customName
                    online: model.online
                    isOn: model.on
                    brightness: model.brightness
                    bulbBusy: model.busy

                    onPowerToggled: function(index, on) {
                        root.powerToggled(index, on);
                    }
                    onBrightnessCommitted: function(index, value) {
                        root.brightnessChanged(index, value);
                    }
                    onRenameRequested: function(index, currentName) {
                        root.openRenameDialog(index, currentName);
                    }
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
            visible: root.bulbsModel.count === 0 && !root.busy
            iconName: root.helperMissing ? "dialog-error-symbolic" : "flashlight-off-symbolic"
            text: root.helperMissing
                ? "NeiWiz engine is missing"
                : (root.lastError.length > 0 ? "Update failed" : "No bulbs found")
            explanation: root.helperMissing
                ? "Run install.sh in the project folder to install the Python helper."
                : (root.lastError.length > 0
                    ? root.lastError
                    : "Check that the bulbs are powered on and on the same network, then try again.")

            PlasmaComponents3.Button {
                Layout.alignment: Qt.AlignHCenter
                icon.name: root.lastError.length > 0 ? "view-refresh-symbolic" : "search-symbolic"
                text: root.lastError.length > 0 ? "Retry" : "Discover bulbs"
                onClicked: {
                    if (root.lastError.length > 0) {
                        root.refreshRequested();
                    } else {
                        root.discoverRequested();
                    }
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            visible: root.bulbsModel.count === 0 && root.busy
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: parent.visible
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Searching for bulbs…"
                opacity: 0.7
            }
        }
    }

    Kirigami.PromptDialog {
        id: renameDialog
        objectName: "renameDialog"

        title: "Rename"
        preferredWidth: Kirigami.Units.gridUnit * 18
        anchors.centerIn: parent
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: "Save"
                icon.name: "dialog-ok"
                onTriggered: renameDialog.accept()
            },
            Kirigami.Action {
                text: "Cancel"
                icon.name: "dialog-cancel"
                onTriggered: renameDialog.reject()
            }
        ]

        onOpened: {
            renameField.forceActiveFocus();
            renameField.selectAll();
        }
        onAccepted: {
            root.renameRequested(root.renameMac, renameField.text);
        }

        PlasmaComponents3.TextField {
            id: renameField
            objectName: "renameField"

            Layout.fillWidth: true
            placeholderText: "Custom name"
            onAccepted: renameDialog.accept()
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: "Leave empty to restore the automatic name."
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }
    }
}
