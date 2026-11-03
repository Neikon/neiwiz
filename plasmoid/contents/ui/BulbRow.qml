import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: root

    property int rowIndex: -1
    property string bulbName: ""
    property string ip: ""
    property string mac: ""
    property string customName: ""
    property bool online: false
    property bool isOn: false
    property int brightness: 100
    property bool bulbBusy: false

    signal powerToggled(int index, bool on)
    signal brightnessCommitted(int index, int value)
    signal renameRequested(int index, string currentName)

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2
    opacity: online ? 1 : 0.55

    RowLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Switch {
            id: powerSwitch

            Layout.alignment: Qt.AlignVCenter
            enabled: root.online && !root.bulbBusy
            onToggled: {
                if (checked !== root.isOn) {
                    root.powerToggled(root.rowIndex, checked);
                }
            }

            Binding {
                target: powerSwitch
                property: "checked"
                value: root.isOn
                restoreMode: Binding.RestoreBindingOrValue
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: root.bulbName
                font.bold: true
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: root.online ? root.ip : root.ip + " · Sin conexión"
                color: root.online ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
        }

        PlasmaComponents3.Slider {
            id: brightnessSlider

            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
            Layout.maximumWidth: Kirigami.Units.gridUnit * 7
            from: 1
            to: 100
            stepSize: 1
            enabled: root.online && root.isOn && !root.bulbBusy
            opacity: enabled ? 1 : 0.4
            onPressedChanged: {
                if (!pressed) {
                    const committed = Math.round(value);
                    if (committed !== root.brightness) {
                        root.brightnessCommitted(root.rowIndex, committed);
                    }
                }
            }

            Binding {
                target: brightnessSlider
                property: "value"
                value: root.brightness
                when: !brightnessSlider.pressed
                restoreMode: Binding.RestoreBindingOrValue
            }
        }

        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            horizontalAlignment: Text.AlignRight
            text: root.online && root.isOn ? Math.round(brightnessSlider.value) + " %" : "—"
            font: Kirigami.Theme.smallFont
            opacity: root.online && root.isOn ? 1 : 0.5
        }

        PlasmaComponents3.ToolButton {
            id: renameButton

            Layout.alignment: Qt.AlignVCenter
            icon.name: "edit-rename"
            text: "Cambiar nombre"
            display: PlasmaComponents3.AbstractButton.IconOnly
            enabled: root.mac.length > 0
            opacity: enabled ? 1 : 0.4
            onClicked: root.renameRequested(root.rowIndex, root.customName)

            PlasmaComponents3.ToolTip {
                text: "Cambiar nombre"
                visible: renameButton.hovered
            }
        }

        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            visible: root.bulbBusy
            running: visible
        }
    }
}
