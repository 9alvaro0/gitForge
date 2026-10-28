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

    @Test("waiting returns, with no issue, when the caller gets to wait() only after waiting started")
    func returnsWhenACallerWaitsLater() async {
        let gate = AsyncGate()
        let release = AsyncGate()
        async let watched: Void = gate.waiting()
        // The caller is held back until `release` opens, so in most runs
        // `waiting` is already suspended when it arrives.
        async let held: Void = {
            await release.wait()
            await gate.wait()
        }()
        await release.waiting()
        release.open()
        await watched
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

    @Test("A cancelled waiting returns at once, so a time limit can end a test whose caller never arrives")
    func cancelledWaitingReturns() async {
        await withKnownIssue {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await AsyncGate().waiting() }
                group.cancelAll()
            }
        }
    }
}
