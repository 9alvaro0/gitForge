import SwiftUI

/// Each `DiffEmptyState` branch tells the user *why* there's nothing to
/// render so a binary or pure rename doesn't read as "the app forgot to
/// load my changes".
struct DiffEmptyContent: View {
    let state: DiffEmptyState

    var body: some View {
        EmptyState(icon: icon, title: copy.title, subtitle: copy.subtitle)
    }

    private var icon: GFIconKind {
        switch state {
        case .empty: .check
        case .binary, .untrackedBinary: .square
        case .renameOnly: .ext
        case .modeChange: .settings
        case .submoduleUpdate: .folder
        }
    }

    private var copy: (title: String, subtitle: String?) {
        switch state {
        case .empty:
            return ("No changes", nil)
        case .binary:
            return ("Binary file", "Diff isn't rendered for non-text content.")
        case .untrackedBinary:
            return ("New binary file",
                    "This file is untracked and isn't text — open it in an external app to inspect it.")
        case .renameOnly:
            return ("Renamed", "The file was moved without content changes.")
        case .modeChange(let from, let to):
            return ("File mode changed", "\(from) → \(to). The contents are unchanged.")
        case .submoduleUpdate(let from, let to):
            return ("Submodule updated", "\(from.prefix(7)) → \(to.prefix(7))")
        }
    }
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .empty)
        .frame(width: 520, height: 200)
        .background(theme.colors.bgCode)
        .appTheme(theme)
}

#Preview("Binary") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .binary)
        .frame(width: 520, height: 200)
        .background(theme.colors.bgCode)
        .appTheme(theme)
}

#Preview("Untracked binary") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .untrackedBinary)
        .frame(width: 520, height: 200)
        .background(theme.colors.bgCode)
        .appTheme(theme)
}

#Preview("Rename only") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .renameOnly)
        .frame(width: 520, height: 200)
        .background(theme.colors.bgCode)
        .appTheme(theme)
}

#Preview("Mode change") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .modeChange(from: "100644", to: "100755"))
        .frame(width: 520, height: 200)
        .background(theme.colors.bgCode)
        .appTheme(theme)
}
