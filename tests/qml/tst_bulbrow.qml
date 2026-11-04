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
