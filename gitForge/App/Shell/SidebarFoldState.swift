import SwiftUI

/// The sidebar column's fold around Settings (settings-redesign §4.1), and
/// the fold worth remembering for the next launch.
///
/// Without the sidebar there is no way to pick a Settings pane, so entering
/// Settings unfolds it and leaving puts it back. What the user does with it
/// meanwhile is theirs: `unfoldedForSettings` only records what Settings did,
/// so leaving folds it again whatever it looks like then, and a fold or an
/// unfold by hand never touches it.
struct SidebarFoldState: Equatable {
    /// What the split view shows. Bound to the `NavigationSplitView`, so a
    /// fold or unfold by the user (the toolbar button, ⌃⌘S, the divider, a
    /// narrow window) lands here. Folded is `.detailOnly`; anything else
    /// shows the sidebar.
    var visibility: NavigationSplitViewVisibility = .all
    /// The sidebar was folded when Settings opened and Settings unfolded it.
    var unfoldedForSettings = false

    /// The fold to save: the sidebar is folded, or Settings holds it open
    /// and will fold it again on leaving. It follows the user, not what
    /// Settings forced, so a relaunch comes up as they left it.
    var isFolded: Bool { unfoldedForSettings || visibility == .detailOnly }

    /// Settings opens: a folded sidebar unfolds for it.
    mutating func enterSettings() {
        guard visibility == .detailOnly else { return }
        visibility = .all
        unfoldedForSettings = true
    }

    /// Settings closes: a sidebar Settings unfolded folds again.
    mutating func leaveSettings() {
        guard unfoldedForSettings else { return }
        visibility = .detailOnly
        unfoldedForSettings = false
    }

    /// A launch: applies the saved fold. Open keeps whatever shape the
    /// sidebar has, and nothing changes while Settings holds it open.
    mutating func restore(folded: Bool) {
        guard !unfoldedForSettings else { return }
        if folded {
            visibility = .detailOnly
        } else if visibility == .detailOnly {
            visibility = .all
        }
    }
}
