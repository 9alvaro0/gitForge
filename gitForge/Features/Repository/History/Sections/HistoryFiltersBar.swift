import SwiftUI

struct HistoryFiltersBar: View {
    @Binding var search: String
    let totalCount: Int
    let matchCount: Int
    /// Focus mode: the focused branch or commit, `nil` when off.
    var focusLabel: String? = nil
    /// A commit is selected, so there's something to focus on.
    var canFocus = false
    var onToggleFocus: () -> Void = {}

    @Environment(\.appTheme) private var theme
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.s12) {
            GFTextField(placeholder: String(localized: "Search subject, author, sha…"), text: $search)
                .frame(maxWidth: 320)
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    if !search.isEmpty {
                        search = ""
                        return .handled
                    }
                    return .ignored
                }
            focusButton
            Spacer()
            MonoText(summary, dim: true)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s8)
        .background(theme.colors.bgContent)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.separator).frame(height: 1) }
        // Hidden ⌘F shortcut in the History toolbar's responder chain — when
        // History is on screen, ⌘F focuses this search field. Lives inside
        // HistoryFiltersBar so the shortcut is automatically scoped to when
        // the bar is rendered (i.e. only the History pane).
        .background(
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    /// "Focus" while off; the focused name with a close mark while on.
    @ViewBuilder
    private var focusButton: some View {
        if let focusLabel {
            Button(action: onToggleFocus) {
                HStack(spacing: Spacing.s4) {
                    Image(systemName: "scope")
                    Text(focusLabel).lineLimit(1)
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.accentOnFill)
                .padding(.horizontal, Spacing.s8)
                .frame(height: 24)
                .background(Capsule().fill(theme.colors.accentFill))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Showing \(focusLabel)'s history only. Click to show everything.")
            .accessibilityLabel("Focused on \(focusLabel)")
            .accessibilityHint("Shows all commits again")
        } else {
            GFButton(title: String(localized: "Focus"), systemImage: "scope", size: .small, disabled: !canFocus,
                     action: onToggleFocus)
                .help("Dim every commit outside the selected commit's history")
        }
    }

    private var summary: String {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let focusLabel {
            return String(localized: "\(matchCount) of \(totalCount) in \(focusLabel)")
        }
        if trimmed.isEmpty {
            return String(localized: "\(totalCount) commits")
        }
        return String(localized: "\(matchCount) of \(totalCount) match")
    }
}

#Preview("Empty search") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var search = ""
    HistoryFiltersBar(search: $search, totalCount: 124, matchCount: 124)
        .frame(width: 1100)
        .appTheme(theme)
}

#Preview("With search") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var search = "feat:"
    HistoryFiltersBar(search: $search, totalCount: 124, matchCount: 17)
        .frame(width: 1100)
        .appTheme(theme)
}
