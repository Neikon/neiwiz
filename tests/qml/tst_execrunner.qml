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
