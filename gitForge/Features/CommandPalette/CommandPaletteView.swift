import SwiftUI

/// ⌘K (artboard `CommandPalette`): a glass panel over a dimmed window, with
/// fuzzy results grouped by kind and the matched letters highlighted.
struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    var onPick: (CommandPaletteItem) -> Void
    var onClose: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var inputFocused: Bool
    @Environment(\.appTheme) private var theme

    private var sections: [CommandPaletteSections.Section] {
        CommandPaletteSections.build(items: items, query: query)
    }

    /// Rows in display order, for arrow-key navigation.
    private var flatRows: [CommandPaletteSections.Row] {
        sections.flatMap(\.rows)
    }

    var body: some View {
        let rows = flatRows
        ZStack(alignment: .top) {
            theme.colors.bgWindow.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                inputRow
                Divider().overlay(theme.colors.separator)
                results(rows)
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
        .onAppear { inputFocused = true; selectedIndex = 0 }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return) {
            if let row = rows[safe: selectedIndex] { onPick(row.item) }
            return .handled
        }
        .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
        .onKeyPress(.downArrow) { selectedIndex = min(max(rows.count - 1, 0), selectedIndex + 1); return .handled }
    }

    private var inputRow: some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
                .accessibilityHidden(true)
            TextField("Search actions, repositories, branches, commits, files…", text: $query)
                .textFieldStyle(.plain)
                .textRole(.title, weight: .regular)
                .foregroundStyle(theme.colors.textPrimary)
                .focused($inputFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .accessibilityLabel("Command")
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 56)
    }

    @ViewBuilder
    private func results(_ rows: [CommandPaletteSections.Row]) -> some View {
        if rows.isEmpty {
            Text("No matches for “\(query)”")
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
                                PaletteRow(row: row, groupTitle: section.kind.title, isActive: index == selectedIndex)
                                    .id(row.id)
                                    .onHover { if $0 { selectedIndex = index } }
                                    .onTapGesture { onPick(row.item) }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.s8)
                    .padding(.top, Spacing.s4)
                    .padding(.bottom, Spacing.s8)
                }
                .frame(maxHeight: 420)
                .onChange(of: selectedIndex) { _, index in
                    if let id = rows[safe: index]?.id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.s16) {
            hint("↑↓", "navigate")
            hint("↵", "run")
            Spacer(minLength: 0)
            hint("esc", "close")
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
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? theme.colors.accentOnFill : theme.colors.textSecondary)
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
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
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

    private var symbol: String {
        switch row.item.kind {
        case .command: "bolt"
        case .repo:    "folder"
        case .branch:  "arrow.triangle.branch"
        case .commit:  "circle.circle"
        case .file:    "doc"
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommandPaletteView(
        items: CommandPaletteItem.previewSamples,
        onPick: { _ in },
        onClose: {}
    )
    .frame(width: 900, height: 640)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
