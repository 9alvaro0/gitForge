import SwiftUI

extension HistorySearchQuery.Field {
    var label: String {
        switch self {
        case .message: String(localized: "Message")
        case .author: String(localized: "Author")
        case .content: String(localized: "Content")
        case .path: String(localized: "Path")
        }
    }

    var systemImage: String {
        switch self {
        case .message: "text.bubble"
        case .author: "person"
        case .content: "text.magnifyingglass"
        case .path: "folder"
        }
    }

    /// The field's placeholder; Content says which of its two searches runs.
    func placeholder(regex: Bool) -> String {
        switch self {
        case .message: String(localized: "Words in the message")
        case .author: String(localized: "Name or email")
        case .content: regex ? String(localized: "Regex in a changed line") : String(localized: "Text added or removed")
        case .path: String(localized: "File or folder")
        }
    }
}

/// "Search history" in the filters bar: adds a criterion's chip.
struct HistorySearchMenu: View {
    let search: HistorySearchStore
    let onAdd: (HistorySearchQuery.Field) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        let available = HistorySearchQuery.Field.allCases.filter { !search.visibleFields.contains($0) }
        Menu {
            ForEach(available) { field in
                Button(field.label, systemImage: field.systemImage) { onAdd(field) }
            }
        } label: {
            // Looks like the bar's other small buttons (`GFButton`, `.small`).
            HStack(spacing: Spacing.s6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Search history")
                    .textRole(.caption, weight: .semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.buttonSmall)
            .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(theme.colors.fillControl))
            .overlay(RoundedRectangle(cornerRadius: Radius.controlSmall).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.controlSmall))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(available.isEmpty)
        .help("Search every commit, not only the loaded ones, by message, author, content or path")
    }
}

/// The search's criteria as chips, AND-combined, with what the search is doing. Return in
/// a chip runs the search; Escape stops it while it runs and ends it otherwise.
struct HistorySearchChips: View {
    let search: HistorySearchStore

    @Environment(\.appTheme) private var theme
    @FocusState private var focusedField: HistorySearchQuery.Field?

    var body: some View {
        HStack(spacing: Spacing.s8) {
            FlowLayout(spacing: Spacing.s6) {
                ForEach(search.visibleFields) { field in
                    chip(field)
                }
            }
            Spacer(minLength: Spacing.s8)
            status
            if search.isSearching || search.isLoadingMore {
                GFButton(title: String(localized: "Stop"), systemImage: "stop.fill", size: .small) { search.stop() }
                    .help("Stop the search; the results so far stay")
            } else {
                GFButton(title: String(localized: "Search"), systemImage: "magnifyingglass", style: .primary, size: .small,
                         disabled: search.draft.isEmpty) { search.run() }
                    .help("Search the whole history (Return)")
            }
            GFButton(title: String(localized: "Clear"), size: .small) { search.clear() }
                .help("Back to the graph and the commit selected before the search")
        }
        .onChange(of: search.visibleFields) { old, new in
            // A chip just added takes the focus, so the user can type right away.
            if new.count > old.count, let added = new.last { focusedField = added }
        }
        .onAppear {
            if let last = search.visibleFields.last { focusedField = last }
        }
    }

    @ViewBuilder
    private var status: some View {
        if search.isSearching {
            HStack(spacing: Spacing.s6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Searching…")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        } else if search.isStopped {
            Text("Stopped")
                .textRole(.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private func chip(_ field: HistorySearchQuery.Field) -> some View {
        let focused = focusedField == field
        return HStack(spacing: Spacing.s4) {
            Image(systemName: field.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .accessibilityHidden(true)
            Text(field.label)
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)
            input(field)
            if field == .content {
                regexToggle
            }
            Button {
                search.remove(field)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove \(field.label)"))
            .help("Remove this criterion")
        }
        .padding(.leading, Spacing.s8)
        .padding(.trailing, Spacing.s4)
        .frame(height: 24)
        .background(Capsule().fill(theme.colors.fillControl))
        .overlay(Capsule().strokeBorder(focused ? theme.colors.accent : theme.colors.strokeControl, lineWidth: 1))
    }

    @ViewBuilder
    private func input(_ field: HistorySearchQuery.Field) -> some View {
        let text = Binding(get: { search.draft[field] }, set: { search.draft[field] = $0 })
        let base = TextField(field.placeholder(regex: search.draft.contentIsRegex), text: text)
            .textFieldStyle(.plain)
            .textRole(field == .message || field == .author ? TypeRole.callout : TypeRole.monoSmall)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(minWidth: 120, idealWidth: 180, maxWidth: 260)
            .fixedSize(horizontal: true, vertical: false)
            .focused($focusedField, equals: field)
            .onSubmit { search.run() }
            .onKeyPress(.escape) {
                if search.isSearching || search.isLoadingMore {
                    search.stop()
                } else {
                    search.clear()
                }
                return .handled
            }
            .accessibilityLabel(field.label)
        if field == .path {
            base
                .textInputSuggestions {
                    ForEach(pathSuggestions, id: \.self) { path in
                        Text(path).textInputCompletion(path)
                    }
                }
                .task { await search.loadTrackedPaths() }
        } else {
            base
        }
    }

    private var pathSuggestions: [String] {
        HistorySearchStore.pathSuggestions(for: search.draft.path, in: search.trackedPaths ?? [])
    }

    /// `.*`: Content as an extended regex over changed lines (`-G`) instead of a string
    /// added or removed (`-S`). Flipping it reruns a search that is showing.
    private var regexToggle: some View {
        let on = search.draft.contentIsRegex
        return Button {
            search.draft.contentIsRegex.toggle()
            if search.isActive, !search.draft.content.isEmpty { search.run() }
        } label: {
            Text(verbatim: ".*")
                .textRole(.monoSmall, weight: .semibold)
                .foregroundStyle(on ? theme.colors.accentOnFill : theme.colors.textTertiary)
                .padding(.horizontal, Spacing.s4)
                .frame(height: 16)
                .background(Capsule().fill(on ? theme.colors.accentFill : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Regular expression"))
        .accessibilityAddTraits(on ? [.isToggle, .isSelected] : .isToggle)
        .help(on ? Text("Matching a regex against changed lines (git log -G)")
                 : Text("Matching text whose count changed (git log -S). Click to use a regex."))
    }
}

#Preview("Chips") {
    @Previewable @State var theme = AppTheme()
    let search: HistorySearchStore = {
        let store = HistorySearchStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/tmp")))
        store.draft = HistorySearchQuery(message: "graph", author: "", content: "pageEnds", contentIsRegex: true)
        store.show(.message)
        store.show(.content)
        store.show(.author)
        return store
    }()
    HistorySearchChips(search: search)
        .padding(Spacing.s12)
        .frame(width: 1000)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
