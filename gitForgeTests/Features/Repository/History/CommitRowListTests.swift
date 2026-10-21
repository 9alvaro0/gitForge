import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// Hosts `CommitRowList` in a real window, inside a `ScrollView` and a
/// `LazyVStack` like the History table, and records what each row's `Canvas`
/// last drew. A row whose canvas never redraws keeps its old entry.
@Suite("History table — commit row identity", .serialized)
@MainActor
struct CommitRowListTests {

    /// What each row's canvas drew last, by sha. Canvases draw off the main actor.
    nonisolated final class DrawLog: @unchecked Sendable {
        private let lock = NSLock()
        private var drawn: [String: String] = [:]
        func record(_ sha: String, _ tag: String) { lock.withLock { drawn[sha] = tag } }
        var snapshot: [String: String] { lock.withLock { drawn } }
    }

    /// Stands in for `CommitRow`: equatable over its data like the real row,
    /// with a canvas that logs the tag it drew for its commit.
    private struct ProbeRow: View, Equatable {
        static func == (lhs: ProbeRow, rhs: ProbeRow) -> Bool { lhs.sha == rhs.sha && lhs.tag == rhs.tag }
        let sha: String
        let tag: String
        let log: DrawLog

        var body: some View {
            let sha = sha
            let tag = tag
            let log = log
            Canvas { context, size in
                log.record(sha, tag)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.gray))
            }
            .frame(height: 20)
        }
    }

    private struct Table: View {
        let commits: [Commit]
        /// Stands in for `graphLayouts`: what the row at each index draws.
        let tags: [String]
        let log: DrawLog
        var onLastRowAppear: ((Commit) -> Void)? = nil

        var body: some View {
            ScrollView {
                LazyVStack(spacing: HistoryTableLayout.rowSpacing) {
                    CommitRowList(commits: commits, onLastRowAppear: onLastRowAppear) { index, commit in
                        ProbeRow(sha: commit.sha, tag: tags[safe: index] ?? "none", log: log)
                            .equatable()
                    }
                }
            }
        }
    }

    /// A window big enough to show every row, rendered without being shown.
    @MainActor private final class Host {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view: NSHostingView<Table>

        init(_ table: Table, until condition: () -> Bool) {
            view = NSHostingView(rootView: table)
            window.contentView = view
            settle(until: condition)
        }

        func show(_ table: Table, until condition: () -> Bool) {
            view.rootView = table
            settle(until: condition)
        }

        /// Lays out and draws again, in short run-loop slices, until `condition`
        /// has held on two passes in a row (a state that flaps does not count) or
        /// two seconds have gone by. It does not fail on a timeout: the caller's
        /// own assertion then reports what is missing. A slow machine gets the
        /// time it needs and a fast one does not wait for a fixed number of passes.
        private func settle(until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            var passesHolding = 0
            while passesHolding < 2, Date() < deadline {
                view.layoutSubtreeIfNeeded()
                window.display()
                passesHolding = condition() ? passesHolding + 1 : 0
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
    }

    private static func commits(_ shas: [String]) -> [Commit] {
        shas.map { GraphFixture.commit($0, parents: []) }
    }

    @Test("A reload that moves commits to new rows redraws every row with its new data")
    func rowsFollowAShift() {
        let log = DrawLog()
        let initial = ["a": "a0", "b": "b0", "c": "c0"]
        let host = Host(Table(commits: Self.commits(["a", "b", "c"]), tags: ["a0", "b0", "c0"], log: log),
                        until: { log.snapshot == initial })
        #expect(log.snapshot == initial)

        // `replaceLog` lands first, with the graph of the old log still in place.
        let shifted = Self.commits(["s", "a", "b", "c"])
        let staleGraph = ["s": "a0", "a": "b0", "b": "c0", "c": "none"]
        host.show(Table(commits: shifted, tags: ["a0", "b0", "c0"], log: log), until: { log.snapshot == staleGraph })
        #expect(log.snapshot == staleGraph)

        // Then the recomputed graph.
        let recomputed = ["s": "s1", "a": "a1", "b": "b1", "c": "c1"]
        host.show(Table(commits: shifted, tags: ["s1", "a1", "b1", "c1"], log: log), until: { log.snapshot == recomputed })
        #expect(log.snapshot == recomputed)

        // Dropping the top row shifts everything back up.
        let shiftedBack = { log.snapshot["a"] == "a2" && log.snapshot["b"] == "b2" && log.snapshot["c"] == "c2" }
        host.show(Table(commits: Self.commits(["a", "b", "c"]), tags: ["a2", "b2", "c2"], log: log), until: shiftedBack)
        #expect(shiftedBack())
    }

    @Test("Only the last row pages in more")
    func pagingHook() {
        let log = DrawLog()
        var appeared: [String] = []
        let onLast: (Commit) -> Void = { appeared.append($0.sha) }
        let host = Host(Table(commits: Self.commits(["a", "b"]), tags: [], log: log, onLastRowAppear: onLast),
                        until: { appeared == ["b"] })
        #expect(appeared == ["b"])
        host.show(Table(commits: Self.commits(["a", "b", "c", "d"]), tags: [], log: log, onLastRowAppear: onLast),
                  until: { appeared == ["b", "d"] })
        #expect(appeared == ["b", "d"])
    }
}
