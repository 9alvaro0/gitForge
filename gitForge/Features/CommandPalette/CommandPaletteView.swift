import AppKit
import SwiftUI

/// ⌘K (artboard `CommandPalette`): a glass panel over a dimmed window, with
/// fuzzy results grouped by kind and the matched letters highlighted.
struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    /// Rows the query itself adds at the head of Pull requests (a pasted
    /// pull request link's), whatever it matches.
    var pinnedItems: (String) -> [CommandPaletteItem] = { _ in [] }
    /// The Search all group the query gives ("Search all of <host>" and what
    /// a search found), after every other; not shown when `pinnedItems` gives
    /// rows (`CommandPaletteSections.build`). Called while the body is built,
    /// so the state it reads redraws the palette when a search lands.
    var trailingItems: (String) -> [CommandPaletteItem] = { _ in [] }
    /// `commandHeld`: ⌘↵, run without closing the palette.
    var onPick: (CommandPaletteItem, _ commandHeld: Bool) -> Void
    var onClose: () -> Void

    @State private var query: String = ""
    @State private var scope: CommandPaletteScope = .all
    @State private var selectedIndex: Int = 0
    /// The selected row: a host search that lands adds and takes away rows,
    /// and the selection stays on this one (`CommandPaletteSections.follow`).
    @State private var selectedItem: CommandPaletteItem?
    @State private var pointer = PointerIntent()
    @FocusState private var inputFocused: Bool
    @Environment(\.appTheme) private var theme

    private var sections: [CommandPaletteSections.Section] {
        CommandPaletteSections.build(items: items, query: query, scope: scope, pinned: pinnedItems(query),
                                     trailing: trailingItems(query))
    }

    var body: some View {
        // Built once per render: a pinned or Search all row is made anew by
        // every build, with its own identity, so the rows the keys walk and
        // the rows drawn have to come from the same one.
        let sections = self.sections
        // Rows in display order, for arrow-key navigation.
        let rows = sections.flatMap(\.rows)
        // The selected row's place now: rows a search landed since may have
        // moved it, or taken it away.
        let active = CommandPaletteSections.selection(keeping: selectedItem, in: rows, fallback: selectedIndex)
        // What a change of the rows is compared by: a rebuilt row is a new
        // item, with the same label.
        let labels = rows.map(\.item.label)
        ZStack(alignment: .top) {
            theme.colors.bgWindow.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                inputRow
                scopeBar
                Divider().overlay(theme.colors.separator)
                results(sections, rows: rows, active: active)
                Divider().overlay(theme.colors.separator)
                footer
            }
            .frame(width: 640)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
            .shadow(color: theme.colors.shadow, radius: 40, y: 30)
            .padding(.top, 120)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command palette")
        }
        .onAppear {
            inputFocused = true
            resetSelection()
            pointer.reset(at: NSEvent.mouseLocation)
        }
        // With a list holding focus (a clicked History or Stashes row), the
        // request in onAppear lands before the field can take it: typing
        // went nowhere and the first ⇥ only moved focus in. Asking again
        // once the panel is on screen makes it stick.
        .task {
            await Task.yield()
            inputFocused = true
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(keys: [.return], phases: .down) { press in
            if let row = rows[safe: active] { onPick(row.item, press.modifiers.contains(.command)) }
            return .handled
        }
        // Rows that change under the selection (a search landing) carry it
        // along: the next change starts from the place and the row it's on
        // now, not from where the keys last left it.
        .onChange(of: labels) { _, _ in
            (selectedIndex, selectedItem) = CommandPaletteSections.follow(selectedItem, at: selectedIndex, in: rows)
        }
        .onKeyPress(.upArrow) { select(max(0, active - 1), in: rows); return .handled }
        .onKeyPress(.downArrow) { select(min(max(rows.count - 1, 0), active + 1), in: rows); return .handled }
    }

    private var inputRow: some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .textRole(.title, weight: .regular)
                .foregroundStyle(theme.colors.textPrimary)
                .focused($inputFocused)
                .onChange(of: query) { _, _ in resetSelection() }
                // On the field itself: the field editor would otherwise
                // take ⇥ to move focus out of the palette.
                .onKeyPress(keys: [.tab, Self.backTab]) { press in
                    let backwards = press.key == Self.backTab || press.modifiers.contains(.shift)
                    setScope(backwards ? scope.previous() : scope.next())
                    return .handled
                }
                // Same for ⎋, which the field editor turns into completion.
                .onKeyPress(.escape) { onClose(); return .handled }
                .accessibilityLabel("Command")
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 56)
    }

    /// The scopes as a segmented row: the current one filled, each one
    /// clickable, ⇥ / ⇧⇥ to step.
    private var scopeBar: some View {
        HStack(spacing: Spacing.s4) {
            ForEach(CommandPaletteScope.ordered, id: \.self) { option in
                let isCurrent = option == scope
                Button(option.title) { setScope(option) }
                    .buttonStyle(.plain)
                    .textRole(.caption, weight: isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? theme.colors.accentOnFill : theme.colors.textSecondary)
                    .padding(.horizontal, Spacing.s8)
                    .frame(height: 22)
                    .background(Capsule().fill(isCurrent ? theme.colors.accentFill : .clear))
                    .contentShape(Capsule())
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .accessibilityHint(option == .all ? String(localized: "Search everything") : String(localized: "Search only \(option.title)"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.bottom, Spacing.s8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scope")
    }

    /// ⇧⇥ can arrive as its own character (U+0019) rather than ⇥ + shift.
    private static let backTab = KeyEquivalent("\u{19}")

    private var placeholder: String {
        switch scope {
        case .all: String(localized: "Search actions, repositories, pull requests, branches, commits, files…")
        case .only(let kind): String(localized: "Search \(kind.title.lowercased())…")
        }
    }

    private func setScope(_ newScope: CommandPaletteScope) {
        scope = newScope
        resetSelection()
        inputFocused = true
    }

    /// The first row, for a new query or scope.
    private func resetSelection() {
        selectedIndex = 0
        selectedItem = nil
    }

    private func select(_ index: Int, in rows: [CommandPaletteSections.Row]) {
        selectedIndex = index
        selectedItem = rows[safe: index]?.item
    }

    @ViewBuilder
    private func results(_ sections: [CommandPaletteSections.Section], rows: [CommandPaletteSections.Row],
                         active: Int) -> some View {
        if rows.isEmpty {
            Text(query.isEmpty ? String(localized: "Nothing in \(scope.title)") : String(localized: "No matches for “\(query)”"))
                .textRole(.body)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(Spacing.s32)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Text(section.kind.title)
                                .textRole(.caption, weight: .semibold)
                                .foregroundStyle(theme.colors.textTertiary)
                                .padding(.horizontal, Spacing.s8)
                                .padding(.top, Spacing.s8)
                                .padding(.bottom, Spacing.s4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.rows) { row in
                                let index = rows.firstIndex { $0.id == row.id } ?? 0
                                Button { onPick(row.item, false) } label: {
                                    PaletteRow(row: row, groupTitle: section.kind.title, isActive: index == active)
                                }
                                .buttonStyle(.plain)
                                .id(row.id)
                                // Only a pointer that moved selects: rows scrolling under a
                                // still one (arrow keys) would pull the selection back.
                                .onHover { inside in
                                    if inside, pointer.moved(to: NSEvent.mouseLocation) { select(index, in: rows) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.s8)
                    .padding(.top, Spacing.s4)
                    .padding(.bottom, Spacing.s8)
                }
                .frame(height: min(Self.listHeight(sections), 420))
                .onChange(of: active) { _, index in
                    if let id = rows[safe: index]?.id { proxy.scrollTo(id) }
                }
            }
        }
    }

    /// The results' height, so the panel hugs a short list: 40 per row,
    /// 28 per group title, plus the list's padding.
    static func listHeight(_ sections: [CommandPaletteSections.Section]) -> CGFloat {
        CGFloat(sections.reduce(0) { $0 + $1.rows.count }) * 40 + CGFloat(sections.count) * 28 + Spacing.s12
    }

    private var footer: some View {
        HStack(spacing: Spacing.s16) {
            hint("↑↓", String(localized: "navigate"))
            hint("↵", String(localized: "run"))
            hint("⌘↵", String(localized: "run without closing"))
            hint("⇥", String(localized: "next scope"))
            Spacer(minLength: 0)
            hint("esc", String(localized: "close"))
        }
        .textRole(.caption)
        .foregroundStyle(theme.colors.textTertiary)
        .padding(.horizontal, Spacing.s16)
        .frame(height: 36)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: Spacing.s4) {
            Text(key).textRole(.monoSmall)
            Text(label)
        }
    }
}

/// One result: icon tile, label with its matched letters, meta and shortcut.
private struct PaletteRow: View {
    let row: CommandPaletteSections.Row
    let groupTitle: String
    let isActive: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s12) {
            icon
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: Radius.controlSmall)
                    .fill(isActive ? theme.colors.accentFill : theme.colors.fillControl))
                .accessibilityHidden(true)
            HStack(spacing: Spacing.s8) {
                Text(highlighted)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                if let meta = row.item.kind == .command ? nil : row.item.hint {
                    Text(meta)
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        // A pull request's `!482 · repo` tells two of the same
                        // title apart: its title is cut first.
                        .layoutPriority(isPull ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.item.kind == .command, let shortcut = row.item.hint {
                Text(shortcut)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.s8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(isActive ? theme.colors.accentSoft : .clear))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.item.label), \(groupTitle)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Matched letters in Semibold and underlined in the accent — never
    /// colour alone.
    private var highlighted: AttributedString {
        var text = AttributedString()
        let matched = Set(row.match?.indices ?? [])
        for (offset, ch) in row.item.label.enumerated() {
            var piece = AttributedString(String(ch))
            if matched.contains(offset) {
                piece.font = AppFont.font(.body, weight: .semibold)
                piece.underlineStyle = .single
                piece.underlineColor = NSColor(theme.colors.accent)
            }
            text.append(piece)
        }
        return text
    }

    /// The row's symbol, or a spinner while its host is being searched.
    @ViewBuilder
    private var icon: some View {
        if row.item.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: row.item.symbol ?? row.item.kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? theme.colors.accentOnFill : theme.colors.textSecondary)
        }
    }

    /// A pull request of the inbox, a pasted link's or one a host search found.
    private var isPull: Bool {
        if case .openPullLink = row.item.action { return true }
        return row.item.kind == .pull
    }
}

/// Tells a hover the pointer caused from one the content caused by
/// scrolling under a pointer that stayed put.
nonisolated struct PointerIntent: Equatable {
    private var last: CGPoint?

    mutating func reset(at location: CGPoint) {
        last = location
    }

    /// `true` when the pointer is somewhere else than at the last call.
    mutating func moved(to location: CGPoint) -> Bool {
        defer { last = location }
        return location != last
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommandPaletteView(
        items: CommandPaletteItem.previewSamples,
        pinnedItems: { CommandPaletteBuilder.linkItems(for: $0, instances: CommandPaletteItem.previewInstances) },
        trailingItems: CommandPaletteItem.previewSearchItems,
        onPick: { _, _ in },
        onClose: {}
    )
    .frame(width: 900, height: 640)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
