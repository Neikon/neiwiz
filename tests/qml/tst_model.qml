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
