import Foundation

/// One row of a Staged / Unstaged file list. A file with changes on both
/// sides appears in each list, so the path alone isn't unique.
nonisolated struct WorkingCopyRowID: Hashable, Sendable {
    let side: WorkingCopySide
    let path: String
}

extension WorkingCopyStore {
    /// The row whose diff is open, for keyboard navigation.
    var selectedRowID: WorkingCopyRowID? {
        selectedWorkingCopyFile.map { WorkingCopyRowID(side: diffSide(for: $0), path: $0.path) }
    }

    /// Opens the row `id` names, if its file is still in `files`.
    func select(_ id: WorkingCopyRowID, in files: [WorkingCopyFile]) {
        guard let file = files.first(where: { $0.path == id.path }) else { return }
        select(file, side: id.side)
    }

    // MARK: ⌘ / Shift ticking

    /// A plain click or arrow move opened `id`: the next Shift run starts there.
    func noteOpened(_ id: WorkingCopyRowID) {
        ticking.setAnchor(id)
    }

    /// ⌘-click, the row's checkbox or Space on `id`.
    func toggleTick(_ id: WorkingCopyRowID) {
        ticking.toggle(id, ticked: &selectedFilePaths)
    }

    /// Shift-click on `id`; `rows` is its section in display order.
    func extendTicks(to id: WorkingCopyRowID, rows: [WorkingCopyRowID]) {
        ticking.extend(to: id, rows: rows, fallback: selectedRowID, ticked: &selectedFilePaths)
    }

    /// Shift-↑↓: grows or shrinks the run by one row and opens that row's
    /// diff. `sections` are the visible Unstaged and Staged rows. Returns the
    /// row, for scrolling; `nil` at a section's end.
    @discardableResult
    func extendTicks(by offset: Int, sections: [[WorkingCopyRowID]]) -> WorkingCopyRowID? {
        guard let target = ticking.stepTarget(by: offset, current: selectedRowID, sections: sections),
              let rows = sections.first(where: { $0.contains(target) }) else { return nil }
        ticking.extend(to: target, rows: rows, fallback: selectedRowID, ticked: &selectedFilePaths)
        select(target, in: status.files)
        return target
    }

    /// Esc: unticks every file. `false` when nothing was ticked, so the key
    /// can go elsewhere.
    @discardableResult
    func clearTicks() -> Bool {
        guard !selectedFilePaths.isEmpty else { return false }
        ticking.forgetRun()
        selectedFilePaths = []
        return true
    }
}
