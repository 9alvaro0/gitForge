import SwiftUI
import AppKit

/// One conflicted file: state glyph (▲ open, ✓ resolved — shape, not just
/// colour), name, and how many conflicts it holds. Side-effects flow back
/// through callbacks so the row stays independent of `RepositoryViewModel`.
struct ConflictFileRow: View {
    let file: ConflictFile
    let isSelected: Bool
    let absoluteURL: URL
    let onSelect: () -> Void
    let onResolveOurs: () -> Void
    let onResolveTheirs: () -> Void
    let onDiscard: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var confirmDiscard = false
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                ConflictStateGlyph(resolved: file.resolved)
                VStack(alignment: .leading, spacing: 0) {
                    Text(fileName)
                        .font(AppFont.font(.monoSmall, weight: isSelected ? .semibold : .regular, monoFamily: theme.monoFont))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(file.path)
        .accessibilityLabel("\(file.path), \(file.resolved ? "resolved" : "\(file.conflicts) conflicts")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { menu }
        // Every other discard in the app confirms first; this one throws
        // away both sides plus any manual resolution of the file.
        .confirmationDialog("Discard conflict in \(fileName)?",
                            isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("Discard conflict", role: .destructive) { onDiscard() }
        } message: {
            Text("The file is reverted to HEAD. Any resolution you made in it is lost. This can't be undone.")
        }
    }

    private var fileName: String { (file.path as NSString).lastPathComponent }

    /// Folder first so files with the same name stay apart; then the state.
    private var subtitle: String {
        let folder = (file.path as NSString).deletingLastPathComponent
        let state = file.resolved ? "Resolved" : (file.conflicts == 1 ? "1 conflict" : "\(file.conflicts) conflicts")
        return folder.isEmpty ? state : "\(state) · \(folder)"
    }

    private var rowFill: Color {
        if isSelected { return theme.colors.fillControl }
        return hovering ? theme.colors.fillHover : .clear
    }

    @ViewBuilder
    private var menu: some View {
        if !file.resolved {
            Button("Resolve using ours") { onResolveOurs() }
            Button("Resolve using theirs") { onResolveTheirs() }
            Button("Discard conflict (revert to HEAD)…", role: .destructive) { confirmDiscard = true }
            Divider()
        }
        Button("Open in editor") { ExternalURL.openFile(absoluteURL) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([absoluteURL]) }
        Divider()
        Button("Copy path") { copy(file.path) }
        Button("Copy filename") { copy(fileName) }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// 16 pt circle: ▲-style "!" on `warnSoft` while open, ✓ on `ok` when done.
struct ConflictStateGlyph: View {
    let resolved: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(resolved ? theme.colors.ok : theme.colors.warnSoft)
            if resolved {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(theme.colors.bgContent)
            } else {
                Circle().strokeBorder(theme.colors.warn, lineWidth: 1)
                Text("!")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.colors.warn)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ForEach(ConflictFile.previewSamples) { file in
            ConflictFileRow(
                file: file,
                isSelected: file.path == ConflictFile.previewSamples.first?.path,
                absoluteURL: URL(fileURLWithPath: "/tmp/\(file.path)"),
                onSelect: {}, onResolveOurs: {}, onResolveTheirs: {}, onDiscard: {}
            )
        }
    }
    .padding(Spacing.s6)
    .frame(width: 280)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
