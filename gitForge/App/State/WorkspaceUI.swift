import Foundation

/// UI-shell state: which workspace section is on screen, the design theme,
/// transient surfaces (command palette, toast, global error alert) and the
/// menu-driven sheet/dialog flags. Independent of the git data so a feature
/// that only needs `theme` doesn't transitively depend on the repo catalog.
@Observable
@MainActor
final class WorkspaceUI {
    /// The defaults key the sidebar's section order is saved under.
    static let sidebarOrderKey = "sidebar.sectionOrder"
    /// The defaults key the last Settings pane is saved under.
    static let settingsPaneKey = "settings.lastPane"

    /// The section on screen. Going into Settings from another section
    /// records it in `sectionBeforeSettings`, and leaving Settings forgets
    /// it, so every way in or out (the menus, ⌘1…⌘n, ⌘K, a repo change)
    /// keeps "Back" right by only assigning this.
    var workspaceSection: WorkspaceSection = .history {
        didSet {
            if workspaceSection == .settings {
                if oldValue != .settings { sectionBeforeSettings = oldValue }
            } else if oldValue == .settings {
                sectionBeforeSettings = nil
            }
        }
    }
    /// Where "Back" in Settings goes: the section Settings was opened from.
    /// `nil` while Settings is not on screen.
    private(set) var sectionBeforeSettings: WorkspaceSection?
    /// The Settings pane on screen, and the one that opens next time.
    /// Written to the defaults when it changes; reading it at launch writes
    /// nothing, even if what was saved is unknown. No initial value:
    /// assigned in `init`, the `didSet` doesn't run there.
    var settingsPane: SettingsPane {
        didSet {
            guard settingsPane != oldValue else { return }
            defaults.set(settingsPane.rawValue, forKey: Self.settingsPaneKey)
        }
    }
    /// The order of the sidebar's sections, one for the whole app. Written
    /// to the defaults when it changes (and removed when it is the default
    /// again, so a later default reaches whoever never changed it); reading
    /// it at launch writes nothing, even if what was saved was incomplete.
    /// No initial value: assigned in `init`, the `didSet` doesn't run there.
    var sidebarOrder: SidebarOrder {
        didSet {
            guard sidebarOrder != oldValue else { return }
            if let saved = sidebarOrder.savedValue {
                defaults.set(saved, forKey: Self.sidebarOrderKey)
            } else {
                defaults.removeObject(forKey: Self.sidebarOrderKey)
            }
        }
    }
    var theme: AppTheme = AppTheme()
    var preferences: AppPreferences = AppPreferences()
    var commandPaletteOpen: Bool = false
    var activeToast: ToastMessage?
    var presentedError: PresentedError?

    /// Flags driven by global menu commands. Views observe these and present
    /// the matching sheet/alert; menus only flip the bool.
    var newBranchSheetVisible: Bool = false
    var discardAllConfirmVisible: Bool = false
    /// "Connect account" sheet (P4 spec §5.2); `ShellView` presents it.
    var connectAccountRequest: ConnectAccountRequest?
    /// "Clone a repository" sheet; `ShellView` presents it.
    var cloneRequest: CloneRequest?

    /// A Settings section to scroll to once Settings shows; cleared then.
    var settingsAnchor: SettingsAnchor?
    /// "New Profile…" from ⌘K: the Identities pane opens its new-profile
    /// sheet and clears this. A fresh `UUID` each time, so asking again
    /// while the pane is up still reaches it.
    var newProfileRequest: UUID?
    /// "Follow Repository…" from ⌘K: the Pull requests pane opens its
    /// add-repository sheet and clears this.
    var followRepositoryRequest: UUID?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sidebarOrder = SidebarOrder(saved: defaults.stringArray(forKey: Self.sidebarOrderKey))
        settingsPane = defaults.string(forKey: Self.settingsPaneKey)
            .flatMap(SettingsPane.init(rawValue:)) ?? .general
    }

    /// Shows Settings on `pane`, or on the last one shown when there is none.
    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        workspaceSection = .settings
    }

    /// Shows Settings on the pane that holds `anchor`'s section, and still
    /// sets the anchor for the Settings view that reads it.
    func openSettings(at anchor: SettingsAnchor) {
        switch anchor {
        case .accounts: openSettings(.accounts)
        case .reviews:  openSettings(.pullRequests)
        }
        settingsAnchor = anchor
    }

    /// Leaves Settings for the section it was opened from (History when
    /// there is none). Does nothing outside Settings.
    func closeSettings() {
        guard workspaceSection == .settings else { return }
        workspaceSection = sectionBeforeSettings ?? .history
    }

    /// Opens Settings on Identities and asks it for a new profile.
    func requestNewProfile() {
        openSettings(.identities)
        newProfileRequest = UUID()
    }

    /// Opens Settings on Pull requests and asks it to follow a repository.
    func requestFollowRepository() {
        openSettings(.pullRequests)
        followRepositoryRequest = UUID()
    }

    /// Opens the clone sheet, unless one is already up: replacing it would
    /// tear down a clone in progress.
    func requestClone(_ request: CloneRequest = CloneRequest()) {
        guard cloneRequest == nil else { return }
        cloneRequest = request
    }
    /// "Add instance" sheet (P4 spec §5.3), prefilled from an unknown remote.
    var addInstanceRequest: AddInstanceRequest?

    /// Shared toast emission for git operations that return an
    /// `IntegrationOutcome` (merge / rebase / cherry-pick / revert / reset /
    /// stash apply). `.conflicts` also routes the user to the conflict
    /// resolver. Avoids copy-pasting the same switch in every action runner.
    func emitToast(for outcome: RepositoryViewModel.IntegrationOutcome,
                   success: String, conflicts: String) {
        switch outcome {
        case .clean:
            activeToast = ToastMessage(message: success, kind: .ok)
        case .conflicts:
            workspaceSection = .conflict
            activeToast = ToastMessage(message: conflicts, kind: .warn)
        case .failed(let message):
            activeToast = ToastMessage(message: message, kind: .error)
        case .cancelled:
            break
        }
    }
}

/// Opens "Connect account", optionally on an instance or reconnecting an account.
struct ConnectAccountRequest: Identifiable, Equatable {
    let id = UUID()
    var instanceId: UUID?
    var replacing: UUID?
}

/// Opens "Add instance", optionally prefilled (an unknown remote's host).
struct AddInstanceRequest: Identifiable, Equatable {
    let id = UUID()
    var kind: HostingInstance.Kind = .gitlab
    var url = ""
}

/// A Settings section other screens link to.
enum SettingsAnchor: Hashable {
    case accounts
    /// What Reviews follows (R3 Ruling 15).
    case reviews
}

/// Opens "Clone a repository", optionally with a URL already in or on a
/// provider's tab.
struct CloneRequest: Identifiable, Equatable {
    enum Source: Hashable { case url, github, gitlab }

    let id = UUID()
    var initialURL: String?
    var source: Source = .url
}
