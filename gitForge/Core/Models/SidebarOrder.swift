import Foundation

/// A View menu entry: a section, its ⌘ number and whether it answers now
/// (pulls-unified §4.8).
struct SectionShortcut: Equatable, Identifiable {
    let section: WorkspaceSection
    /// 1-based place in the whole order, with or without a repository.
    let number: Int
    /// Whether the section is shown in the sidebar now.
    let isEnabled: Bool

    var id: WorkspaceSection { section }

    /// The digit that, with ⌘, opens the section: `number` for 1 to 9, and
    /// none from 10 on, which has no single-key shortcut.
    var keyCharacter: Character? {
        (1...9).contains(number) ? Character(String(number)) : nil
    }
}

/// The order of the sidebar's sections, one for the whole app
/// (pulls-unified §4.7).
///
/// A plain value with no views, so everything that can be done to the order
/// is tested without them: restoring a saved one, moving a section, going
/// back to the default, and which sections the list shows.
struct SidebarOrder: Equatable {
    /// What a person can do to the order from the sidebar.
    enum Edit: Equatable {
        /// A drag, in `sections` offsets, as `onMove` gives them.
        case move(fromOffsets: IndexSet, toOffset: Int)
        case moveUp(WorkspaceSection)
        case moveDown(WorkspaceSection)
        /// "Reset Order": back to the default.
        case reset
    }

    /// Always a permutation of `WorkspaceSection.workspaceItems`: all six,
    /// none twice. Settings is not in it.
    private(set) var sections: [WorkspaceSection]

    /// The default order.
    init() {
        sections = WorkspaceSection.workspaceItems
    }

    /// The order a previous run saved (`savedValue`), made safe to use.
    ///
    /// What isn't a workspace section (an old name, Settings) and what
    /// repeats is dropped, the first of a repeat staying. The sections left
    /// out come back at their default position, so one added in a future
    /// version takes the number it has by default. Nothing saved, an empty
    /// list or something that isn't a list is the default order.
    init(saved: [String]?) {
        let defaultOrder = WorkspaceSection.workspaceItems
        var restored: [WorkspaceSection] = []
        for value in saved ?? [] {
            guard let section = WorkspaceSection(rawValue: value),
                  defaultOrder.contains(section), !restored.contains(section) else { continue }
            restored.append(section)
        }
        for (index, section) in defaultOrder.enumerated() where !restored.contains(section) {
            restored.insert(section, at: min(index, restored.count))
        }
        sections = restored
    }

    /// Whether this is the default order.
    var isDefault: Bool { sections == WorkspaceSection.workspaceItems }

    /// What to keep for the next run: the raw values in order, or `nil` for
    /// the default, which is forgotten instead of saved so that a person who
    /// never changed the order, or reset it, follows the default of each
    /// version.
    var savedValue: [String]? {
        isDefault ? nil : sections.map(\.rawValue)
    }

    /// Whether `section` has another before it.
    func canMoveUp(_ section: WorkspaceSection) -> Bool {
        guard let index = sections.firstIndex(of: section) else { return false }
        return index > sections.startIndex
    }

    /// Whether `section` has another after it.
    func canMoveDown(_ section: WorkspaceSection) -> Bool {
        guard let index = sections.firstIndex(of: section) else { return false }
        return index < sections.index(before: sections.endIndex)
    }

    /// Does `edit`. One that can't be done (the first going up, offsets the
    /// list no longer has) changes nothing: a drag can arrive after the list
    /// has changed under it.
    mutating func apply(_ edit: Edit) {
        switch edit {
        case .move(let offsets, let destination):
            move(fromOffsets: offsets, toOffset: destination)
        case .moveUp(let section):
            guard canMoveUp(section), let index = sections.firstIndex(of: section) else { return }
            sections.swapAt(index, index - 1)
        case .moveDown(let section):
            guard canMoveDown(section), let index = sections.firstIndex(of: section) else { return }
            sections.swapAt(index, index + 1)
        case .reset:
            sections = WorkspaceSection.workspaceItems
        }
    }

    /// What the list shows: every section with a repository open; without
    /// one, Pull requests alone, whose Team and Mine need none, wherever the
    /// order puts it (pulls-unified §4.1).
    func visible(hasRepository: Bool) -> [WorkspaceSection] {
        hasRepository ? sections : [.pulls]
    }

    /// The View menu: every section in the order, each with the ⌘ number of
    /// its place in the whole order, so the numbers don't move without a
    /// repository. One answers only if the sidebar shows it, which without a
    /// repository is Pull requests alone (pulls-unified §4.8).
    func shortcuts(hasRepository: Bool) -> [SectionShortcut] {
        let shown = visible(hasRepository: hasRepository)
        return sections.enumerated().map { index, section in
            SectionShortcut(section: section, number: index + 1, isEnabled: shown.contains(section))
        }
    }

    /// The `onMove` semantics: the sections at `offsets` go before the one
    /// that was at `destination` (`sections.count` for the end). Offsets that
    /// aren't all in range, none at all, or a destination outside the list
    /// move nothing.
    private mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty,
              offsets.allSatisfy({ sections.indices.contains($0) }),
              (0...sections.count).contains(destination) else { return }
        let moved = offsets.map { sections[$0] }
        var rest = sections.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moved, at: destination - offsets.count(in: 0..<destination))
        sections = rest
    }
}
