import Foundation

/// UI-shell state: which workspace section is on screen, the design theme,
/// transient surfaces (command palette, toast, global error alert) and the
/// menu-driven sheet/dialog flags. Independent of the git data so a feature
/// that only needs `theme` doesn't transitively depend on the repo catalog.
@Observable
@MainActor
final class WorkspaceUI {
    var workspaceSection: WorkspaceSection = .history
    var theme: AppTheme = AppTheme()
    var commandPaletteOpen: Bool = false
    var activeToast: ToastMessage?
    var presentedError: PresentedError?

    /// Flags driven by global menu commands. Views observe these and present
    /// the matching sheet/alert; menus only flip the bool.
    var newBranchSheetVisible: Bool = false
    var discardAllConfirmVisible: Bool = false
}
