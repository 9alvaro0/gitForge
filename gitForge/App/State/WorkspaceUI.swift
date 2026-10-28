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

    var workspaceSection: WorkspaceSection = .history
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sidebarOrder = SidebarOrder(saved: defaults.stringArray(forKey: Self.sidebarOrderKey))
    }

    /// Shows Settings, scrolled to `anchor` when given.
    func openSettings(at anchor: SettingsAnchor? = nil) {
        workspaceSection = .settings
        settingsAnchor = anchor
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

    /// Toast for a checkout started from the UI. A refusal over local
    /// changes shows nothing here: the shell asks whether to discard them.
    func emitToast(for outcome: RepositoryViewModel.CheckoutOutcome) {
        switch outcome {
        case .done(let message):
            activeToast = ToastMessage(message: message, kind: .ok)
        case .failed(let message):
            activeToast = ToastMessage(message: message, kind: .error)
        case .askingToDiscard, .cancelled:
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
