import Foundation

/// How many times something ran: a parser, an observation's `onChange`.
/// Either may run off the main actor.
final class CallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
