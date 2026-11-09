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
            bulbName: "Bulb EEFF"
            mac: "aabbccddeeff"
            customName: "Despacho"
            online: true
        }
    }

    Component { id: spyComponent; SignalSpy { signalName: "renameRequested" } }
    Component { id: brightnessSpyComponent; SignalSpy { signalName: "brightnessCommitted" } }

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
        compare(slider.Accessible.name, "Brightness of Bulb EEFF")
    }
}
