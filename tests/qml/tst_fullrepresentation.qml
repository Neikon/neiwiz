import QtQuick
import QtTest
import "../../plasmoid/contents/ui" as NeiWiz

TestCase {
    name: "FullRepresentation"
    id: testCase
    when: windowShown

    Component {
        id: fullComponent
        NeiWiz.FullRepresentation {
            property ListModel sourceModel: ListModel {
                ListElement {
                    ip: "192.168.1.10"
                    mac: "aabbccddeeff"
                    name: "Bulb EEFF"
                    customName: "Despacho"
                    online: true
                    on: false
                    brightness: 50
                    busy: false
                }
                ListElement {
                    ip: "192.168.1.11"
                    mac: "112233445566"
                    name: "Bulb 5566"
                    customName: "Kitchen"
                    online: true
                    on: false
                    brightness: 50
                    busy: false
                }
            }
            bulbsModel: sourceModel
        }
    }

    Component { id: spyComponent; SignalSpy { signalName: "renameRequested" } }

    function test_dialog_follows_mac_when_model_reorders() {
        let panel = createTemporaryObject(fullComponent, testCase)
        verify(panel)
        let dialog = findChild(panel, "renameDialog")
        let field = findChild(dialog, "renameField")
        verify(dialog)
        verify(field)
        let spy = spyComponent.createObject(testCase, {target: panel})
        verify(spy.valid)
        panel.openRenameDialog("112233445566", "Kitchen")
        tryCompare(field, "text", "Kitchen")
        panel.sourceModel.move(1, 0, 1)
        dialog.accept()
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "112233445566")
        compare(spy.signalArguments[0][1], "Kitchen")
    }

    function test_status_shows_updating_while_busy() {
        let panel = createTemporaryObject(fullComponent, testCase)
        let label = findChild(panel, "statusLabel")
        verify(label)
        panel.busy = true
        panel.allOffline = true
        compare(label.text, "Updating…")
        panel.busy = false
        compare(label.text, "Offline")
    }
}
