import Testing

@Suite("AsyncGate")
struct AsyncGateTests {

    @Test("waiting returns, with no issue, once a caller is suspended in wait()")
    func returnsWhenACallerWaits() async {
        let gate = AsyncGate()
        async let held: Void = gate.wait()
        await gate.waiting()
        #expect(gate.isWaiting)
        gate.open()
        await held
    }

    @Test("waiting records an issue when nothing is suspended in wait() before the timeout")
    func recordsAnIssueOnTimeout() async {
        await withKnownIssue {
            await AsyncGate().waiting(timeout: .milliseconds(30))
        }
    }
}
