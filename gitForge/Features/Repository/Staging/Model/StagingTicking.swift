import AppKit

/// Finder-style ticking in the Staged / Unstaged lists. ⌘-click (or the
/// checkbox, or Space) flips one row and makes it the anchor; Shift-click and
/// Shift-↑↓ tick the run from the anchor to a target row. Pulling the run's
/// far end back shrinks it again, but a run never unticks a file that was
/// ticked before it started. A run stays inside one section: Staged and
/// Unstaged each have their own batch bar.
nonisolated struct StagingTicking: Equatable, Sendable {
    /// Where the next run starts. Set by a plain click or arrow move too, so
    /// Shift-click right after opening a row ticks from that row.
    private(set) var anchor: WorkingCopyRowID?
    /// The run's far end — where Shift-↑↓ moves from.
    private(set) var head: WorkingCopyRowID?
    /// Paths the current run ticked that weren't ticked before it. The next
    /// extend unticks them before ticking its own run.
    private(set) var runAdded: Set<String> = []

    /// A plain click or arrow move landed on `id`: the next run starts there.
    mutating func setAnchor(_ id: WorkingCopyRowID?) {
        anchor = id
        head = nil
        runAdded = []
    }

    /// The ticks changed some other way (select-all, a batch action, Esc):
    /// the current run is no longer one to shrink.
    mutating func forgetRun() {
        head = nil
        runAdded = []
    }

    /// ⌘-click / checkbox / Space: flips `id`'s tick and anchors there.
    mutating func toggle(_ id: WorkingCopyRowID, ticked: inout Set<String>) {
        if ticked.contains(id.path) {
            ticked.remove(id.path)
        } else {
            ticked.insert(id.path)
        }
        setAnchor(id)
    }

    /// Shift-click / Shift-↑↓: ticks every row from the anchor to `target`.
    /// `rows` is the target's section in display order. Without an anchor in
    /// that section the run starts at `fallback` (the row whose diff is open)
    /// when it's there, else at `target` itself.
    mutating func extend(to target: WorkingCopyRowID,
                         rows: [WorkingCopyRowID],
                         fallback: WorkingCopyRowID?,
                         ticked: inout Set<String>) {
        guard let end = rows.firstIndex(of: target) else { return }
        let start: Int
        if let anchor, let i = rows.firstIndex(of: anchor) {
            start = i
        } else if let fallback, let i = rows.firstIndex(of: fallback) {
            start = i
            setAnchor(fallback)
        } else {
            start = end
            setAnchor(target)
        }
        let run = Set(rows[min(start, end)...max(start, end)].map(\.path))
        ticked.subtract(runAdded)
        runAdded = run.subtracting(ticked)
        ticked.formUnion(run)
        head = target
    }

    /// The row Shift-↑↓ extends the run to: one row on from the run's far end
    /// (or `current`, the open row, before a run exists), clamped to the
    /// section that row is in. `nil` at the section's end or with nowhere to
    /// start, so the key press does nothing.
    func stepTarget(by offset: Int,
                    current: WorkingCopyRowID?,
                    sections: [[WorkingCopyRowID]]) -> WorkingCopyRowID? {
        for from in [head, current].compactMap({ $0 }) {
            guard let rows = sections.first(where: { $0.contains(from) }),
                  let i = rows.firstIndex(of: from) else { continue }
            let j = i + offset
            return rows.indices.contains(j) ? rows[j] : nil
        }
        return nil
    }
}

/// What a click on a Staged / Unstaged row does, from the modifiers held.
nonisolated enum StagingRowClick: Equatable, Sendable {
    /// Open the row's diff.
    case open
    /// ⌘-click: flip the row's tick.
    case toggleTick
    /// Shift-click: tick the run from the anchor to this row.
    case extendTicks

    init(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            self = .toggleTick
        } else if modifiers.contains(.shift) {
            self = .extendTicks
        } else {
            self = .open
        }
    }
}

/// The ⌘ shortcuts of the Staged / Unstaged lists.
nonisolated enum StagingKeyCommand: Equatable, Sendable {
    /// ⌘A: tick every file in the open row's section.
    case tickSection
    /// ⌘⌫: discard the ticked files, or the open one, after asking.
    case discard

    /// `characters` as the key gives them without modifiers, lowercased.
    init?(characters: String, modifiers: NSEvent.ModifierFlags) {
        guard modifiers == .command else { return nil }
        switch characters {
        case "a": self = .tickSection
        case "\u{7F}": self = .discard
        default: return nil
        }
    }
}
