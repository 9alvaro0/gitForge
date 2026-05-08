import SwiftUI

/// `.gf-cmdk-*` — fuzzy palette overlaid via .sheet/.fullScreenCover from the app root.
struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    var onPick: (CommandPaletteItem) -> Void
    var onClose: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var inputFocused: Bool
    @Environment(\.appTheme) private var theme

    private var filteredItems: [CommandPaletteItem] {
        if query.isEmpty {
            return Array(items.prefix(12))
        }
        return Array(items.filter { $0.matches(query) }.prefix(16))
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.palette.bg0.opacity(0.6).ignoresSafeArea().onTapGesture { onClose() }
            VStack(spacing: DesignTokens.Spacing.none) {
                inputRow
                Rectangle().fill(theme.palette.line).frame(height: 1)
                resultsList
                Rectangle().fill(theme.palette.line).frame(height: 1)
                footer
            }
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl).stroke(theme.palette.lineStrong, lineWidth: 1))
            .frame(maxWidth: 560)
            .shadow(color: theme.palette.shadowColor, radius: 40, y: 20)
            .padding(.top, 100)
        }
        .onAppear { inputFocused = true; selectedIndex = 0 }
        .onKeyPress(.escape) {
            onClose(); return .handled
        }
        .onKeyPress(.return) {
            if let item = filteredItems[safe: selectedIndex] { onPick(item) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1); return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(filteredItems.count - 1, selectedIndex + 1); return .handled
        }
    }

    private var inputRow: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            GFIcon(kind: .search, size: 14, stroke: theme.palette.fg3)
            TextField("Search repos, commits, branches, files…", text: $query)
                .textFieldStyle(.plain)
                .font(AppFont.sans(14))
                .foregroundStyle(theme.palette.fg1)
                .focused($inputFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
            Kbd(text: "esc")
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.none) {
                if filteredItems.isEmpty {
                    Text("No matches for “\(query)”")
                        .font(AppFont.sans(12))
                        .foregroundStyle(theme.palette.fg3)
                        .padding(DesignTokens.Spacing.xhuge)
                }
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                    paletteRow(item: item, isActive: idx == selectedIndex)
                        .onHover { if $0 { selectedIndex = idx } }
                        .onTapGesture { onPick(item) }
                }
            }
            .padding(DesignTokens.Spacing.xs)
        }
        .frame(maxHeight: 380)
    }

    @ViewBuilder
    private func paletteRow(item: CommandPaletteItem, isActive: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            GFIcon(kind: item.icon, size: 14, stroke: isActive ? theme.palette.accent : theme.palette.fg3)
            Text(item.label)
                .font(AppFont.sans(13))
                .lineLimit(1)
                .foregroundStyle(isActive ? theme.palette.accent : theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.tag.uppercased())
                .font(AppFont.mono(10, family: theme.monoFont))
                .foregroundStyle(isActive ? theme.palette.accent.opacity(0.85) : theme.palette.fg3)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg3))
            if let hint = item.hint {
                Text(hint)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(isActive ? theme.palette.accent.opacity(0.85) : theme.palette.fg3)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(isActive ? theme.palette.accentSoft : .clear))
        .contentShape(.rect)
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.xxxl) {
            HStack(spacing: DesignTokens.Spacing.xs) { Kbd(text: "↑↓"); Text("navigate") }
            HStack(spacing: DesignTokens.Spacing.xs) { Kbd(text: "↵"); Text("select") }
            HStack(spacing: DesignTokens.Spacing.xs) { Kbd(text: "esc"); Text("close") }
        }
        .font(AppFont.sans(11))
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, DesignTokens.Spacing.xxxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.bg2)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    CommandPaletteView(
        items: CommandPaletteItem.previewSamples,
        onPick: { _ in },
        onClose: {}
    )
    .frame(width: 720, height: 600)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
#endif
