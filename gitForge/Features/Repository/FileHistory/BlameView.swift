import SwiftUI
import AppKit

/// The Blame tab: the file's lines with, in a gutter, who last changed each
/// run of them, when, and in which commit. Fills in as `git blame` streams;
/// the code is coloured like the diff.
struct BlameView: View {
    let store: BlameStore
    /// Opens a commit in History (a click on a gutter group).
    let onOpenCommit: (String) -> Void
    /// Selects a commit in the History tab of this sheet.
    let onShowInHistory: (String) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    /// `row → highlighted line`; plain text until it lands.
    @State private var highlighted: [Int: AttributedString] = [:]
    /// The commit under the pointer: its whole group lights up.
    @State private var hoveredSha: String?

    static let gutterWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(theme.colors.separator).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.colors.bgCode)
        .task(id: highlightKey) { await highlight() }
        .onChange(of: preferences.diffIgnoreWhitespace) { store.run { await store.reload() } }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.s8) {
            if !store.backStack.isEmpty {
                IconButton(symbol: "chevron.backward", size: 12, accessibilityLabel: String(localized: "Back")) {
                    store.run { await store.goBack() }
                }
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to the blame before (⌘[)")
            }
            locationLabel
            Spacer(minLength: Spacing.s8)
            if store.isBlaming, store.phase == .loaded, !store.lines.isEmpty {
                ProgressView(value: store.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                Text("Blaming \(store.blamedLineCount) of \(store.lines.count) lines")
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize()
            }
            if let line = store.selectedLine {
                GFButton(title: String(localized: "Blame before this commit"), systemImage: "arrow.uturn.backward",
                         size: .small, disabled: store.origin(before: line) == nil) {
                    store.run { await store.blameBefore(line: line) }
                }
                .help(beforeHelp(line))
            }
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 36)
        .background(theme.colors.bgContent)
    }

    /// "Working tree" or the revision, then the path when it isn't the one
    /// the sheet opened on (walking back past a rename).
    private var locationLabel: some View {
        HStack(spacing: Spacing.s6) {
            if let revision = store.location.revision {
                Text("At")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                Text(revisionLabel(revision))
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                if let summary = store.commits[revision]?.summary {
                    Text(summary)
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text("Working tree")
                    .textRole(.callout, weight: .medium)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Text("·").foregroundStyle(theme.colors.textQuaternary)
            FilePathText(path: store.location.path)
                .textRole(.monoSmall)
                .lineLimit(1)
                .truncationMode(.head)
                .help(store.location.path)
        }
    }

    /// A full SHA shortened; anything else (`HEAD`, `abc^`) as it is.
    private func revisionLabel(_ revision: String) -> String {
        revision.count == 40 || revision.count == 64 ? String(revision.prefix(7)) : revision
    }

    private func beforeHelp(_ line: Int) -> String {
        guard let commit = store.commit(at: line) else { return String(localized: "This line isn’t blamed yet") }
        if store.origin(before: line) == nil {
            return String(localized: "\(commit.shortSha) is where the history starts: there is nothing before it")
        }
        return String(localized: "Blame the file as it was before \(commit.shortSha), keeping this line in view")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            DiffLoadingSkeleton()
        case .binary:
            EmptyState(symbol: "doc.zipper", title: String(localized: "Binary file"),
                       subtitle: String(localized: "There are no lines to blame."))
        case .tooLarge:
            EmptyState(symbol: "doc.badge.ellipsis", title: String(localized: "File too large to blame"),
                       subtitle: String(localized: "Use git blame in a terminal for this one."))
        case .failed(let message):
            EmptyState(symbol: "exclamationmark.triangle", title: String(localized: "Couldn’t blame this file"),
                       subtitle: message)
        case .loaded:
            if store.lines.isEmpty {
                EmptyState(symbol: "doc", title: String(localized: "Empty file"),
                           subtitle: String(localized: "There are no lines to blame."))
            } else {
                lineList
            }
        }
    }

    private var lineList: some View {
        let wrap = preferences.diffWrapLongLines
        let numberWidth = CGFloat(max(3, String(store.lines.count).count)) * 8 + Spacing.s12
        return GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(wrap ? [.vertical] : [.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.lines.indices, id: \.self) { row in
                            lineRow(row, numberWidth: numberWidth, wrap: wrap)
                                .id(row + 1)
                        }
                    }
                    .frame(minWidth: geo.size.width, maxWidth: wrap ? geo.size.width : nil, alignment: .topLeading)
                }
                .onChange(of: store.focusSerial, initial: true) {
                    guard let line = store.focusLine else { return }
                    // After the rows for the new lines are in.
                    Task { @MainActor in proxy.scrollTo(line, anchor: .center) }
                }
            }
        }
    }

    private func lineRow(_ row: Int, numberWidth: CGFloat, wrap: Bool) -> some View {
        let line = row + 1
        let commit = store.commit(at: line)
        let sha = store.sha(at: line)
        return BlameLineRow(
            number: line,
            text: store.lines[row],
            attributed: highlighted[row],
            commit: commit,
            isGroupStart: store.startsGroup(line),
            isSelected: store.selectedLine == line,
            isGroupHovered: sha != nil && sha == hoveredSha,
            numberWidth: numberWidth,
            wrap: wrap,
            onSelect: { store.selectedLine = line },
            onOpenCommit: { if let commit, !commit.isUncommitted { onOpenCommit(commit.sha) } },
            onHover: { hovering in
                if hovering { hoveredSha = sha } else if hoveredSha == sha { hoveredSha = nil }
            }
        )
        .contextMenu { menu(line: line, commit: commit) }
    }

    @ViewBuilder
    private func menu(line: Int, commit: BlameCommit?) -> some View {
        Button("Blame before this commit") {
            store.run { await store.blameBefore(line: line) }
        }
        .disabled(store.origin(before: line) == nil)
        if let commit, !commit.isUncommitted {
            Button("Open commit in History") { onOpenCommit(commit.sha) }
            Button("Show in file history") { onShowInHistory(commit.sha) }
            Divider()
            Button("Copy SHA") { copy(commit.sha) }
        }
        Button("Copy line") { copy(store.lines[line - 1]) }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: Highlighting

    private struct HighlightKey: Equatable {
        let location: BlameStore.Location
        let lineCount: Int
        let mode: String
    }

    private var highlightKey: HighlightKey {
        var location = store.location
        location.line = nil
        return HighlightKey(location: location, lineCount: store.lines.count, mode: theme.effectiveMode.rawValue)
    }

    /// Colours the file a chunk at a time, as the diff pane does, up to the
    /// same size limit.
    private func highlight() async {
        highlighted = [:]
        let lines = store.lines
        guard let language = DiffSyntaxHighlighter.languageId(for: store.location.path),
              !lines.isEmpty, lines.count <= DiffPane.highlightLineLimit else { return }
        let css = DiffSyntaxHighlighter.css(for: SyntaxPalette.make(theme.variant))
        let themeId = theme.effectiveMode.rawValue
        var output: [Int: AttributedString] = [:]
        for chunk in BlameHighlight.chunks(of: lines) {
            let coloured = await DiffSyntaxHighlighter.shared.tokenize(hunk: chunk, language: language,
                                                                       css: css, themeId: themeId)
            if Task.isCancelled { return }
            output.merge(coloured) { $1 }
            highlighted = output
        }
    }
}

/// One line of the blame: the gutter (filled on the first line of a run
/// from one commit), the line number and the code.
private struct BlameLineRow: View {
    let number: Int
    let text: String
    let attributed: AttributedString?
    /// `nil` while git hasn't blamed the line yet.
    let commit: BlameCommit?
    let isGroupStart: Bool
    let isSelected: Bool
    let isGroupHovered: Bool
    let numberWidth: CGFloat
    let wrap: Bool
    let onSelect: () -> Void
    let onOpenCommit: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            gutter
            Text(String(number))
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(isSelected ? theme.colors.textSecondary : theme.colors.textQuaternary)
                .frame(width: numberWidth, alignment: .trailing)
                .padding(.trailing, Spacing.s8)
            code
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: wrap)
                .padding(.trailing, Spacing.s12)
                .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(perform: onSelect)
            if !wrap { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, minHeight: theme.density.metrics.diffLine, alignment: .leading)
        .background(isSelected ? theme.colors.accentSoft : Color.clear)
        .overlay(alignment: .top) {
            if isGroupStart, number > 1 {
                Rectangle().fill(theme.colors.separator).frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Open commit in History"), onOpenCommit)
    }

    @ViewBuilder
    private var code: some View {
        if let attributed {
            Text(attributed)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
        } else {
            Text(text.isEmpty ? " " : text)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                .foregroundStyle(Color(hex: SyntaxPalette.make(theme.variant).plain))
        }
    }

    // MARK: Gutter

    private var gutter: some View {
        Button(action: onOpenCommit) {
            HStack(spacing: Spacing.s8) {
                if isGroupStart {
                    groupLabel
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .padding(.horizontal, Spacing.s8)
            .frame(width: BlameView.gutterWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(gutterFill)
            .overlay(alignment: .leading) {
                if commit?.isUncommitted == true {
                    Rectangle().fill(theme.colors.warn).frame(width: 2)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.colors.separator).frame(width: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(commit == nil || commit?.isUncommitted == true)
        .onHover(perform: onHover)
        .help(gutterHelp)
    }

    @ViewBuilder
    private var groupLabel: some View {
        if let commit {
            if commit.isUncommitted {
                Text("Not committed yet")
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.warn)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Text(DateDisplayMode.elapsed(since: commit.authorDate))
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .leading)
                Text(commit.authorName)
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 90, alignment: .leading)
                Text(commit.summary)
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("…")
                .textRole(.caption)
                .foregroundStyle(theme.colors.textQuaternary)
            Spacer(minLength: 0)
        }
    }

    private var gutterFill: Color {
        if commit?.isUncommitted == true { return theme.colors.warnSoft }
        return isGroupHovered ? theme.colors.fillHover : theme.colors.bgContent
    }

    private var gutterHelp: String {
        guard let commit else { return String(localized: "Not blamed yet") }
        if commit.isUncommitted { return String(localized: "Not committed yet") }
        let date = DateDisplayMode.absolute.format(commit.authorDate)
        return String(localized: "\(commit.shortSha) · \(commit.authorName) · \(date)\n\(commit.summary)\nClick to open in History")
    }

    private var accessibilityText: String {
        let owner: String
        if let commit {
            owner = commit.isUncommitted
                ? String(localized: "not committed yet")
                : String(localized: "\(commit.authorName), \(DateDisplayMode.elapsed(since: commit.authorDate)), \(commit.summary)")
        } else {
            owner = String(localized: "not blamed yet")
        }
        return String(localized: "Line \(number): \(text). \(owner)")
    }
}
