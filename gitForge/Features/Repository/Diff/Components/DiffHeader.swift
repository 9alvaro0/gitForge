import SwiftUI

/// File strip above the diff: status badge, path, `+N −M`, the
/// Unified/Split switch, the view options (wrap, whitespace) and the
/// optional actions. Action handlers are
/// optional so callers can hide the buttons where they don't apply
/// (history-mode diffs have no editor target; only History collapses the pane).
struct DiffHeader: View {
    let file: String?
    var status: StatusTag.Kind? = nil
    var stats: DiffStats? = nil
    @Binding var viewMode: DiffPane.ViewMode
    /// Offer Hide whitespace (only diffs that come from git can honour it).
    var canHideWhitespace: Bool = false
    let onOpenInEditor: (() -> Void)?
    let onClose: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    var body: some View {
        HStack(spacing: Spacing.s8) {
            if let status {
                StatusTag(kind: status)
            }
            path
            if let stats, !stats.isEmpty {
                statsView(stats)
            }
            SegmentedControl<DiffPane.ViewMode>(
                [(.unified, "Unified"), (.split, "Split")],
                selection: $viewMode
            )
            .fixedSize()
            optionsMenu
            if let onOpenInEditor {
                IconButton(symbol: "arrow.up.right.square", accessibilityLabel: "Open in editor", action: onOpenInEditor)
                    .help("Open in editor")
            }
            if let onClose {
                IconButton(symbol: "xmark", accessibilityLabel: "Hide diff pane", action: onClose)
                    .help("Hide diff pane")
            }
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 40)
        .background(theme.colors.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }

    /// Wrap lines and Hide whitespace. Both are app-wide preferences (wrap is
    /// also in Settings), so every diff follows the last choice. The icon
    /// takes the accent while whitespace is hidden, since lines are missing.
    private var optionsMenu: some View {
        @Bindable var preferences = preferences
        let hiding = canHideWhitespace && preferences.diffIgnoreWhitespace
        return Menu {
            Toggle("Wrap lines", isOn: $preferences.diffWrapLongLines)
            if canHideWhitespace {
                Toggle("Hide whitespace", isOn: $preferences.diffIgnoreWhitespace)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hiding ? theme.colors.accent : theme.colors.textSecondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Diff options")
        .accessibilityValue(hiding ? "Whitespace hidden" : "")
        .help(hiding ? "Diff options · whitespace hidden" : "Diff options")
    }

    /// Folder dim, file name bright: the name is what the eye scans.
    private var path: some View {
        let full = file ?? "—"
        let directory = (full as NSString).deletingLastPathComponent
        let name = (full as NSString).lastPathComponent
        let prefix = directory.isEmpty ? "" : directory + "/"
        return Text("\(Text(prefix).foregroundStyle(theme.colors.textQuaternary))\(Text(name).foregroundStyle(theme.colors.textPrimary))")
            .font(AppFont.font(.mono, monoFamily: theme.monoFont))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(full)
    }

    private func statsView(_ stats: DiffStats) -> some View {
        HStack(spacing: Spacing.s4) {
            if stats.additions > 0 {
                Text("+\(stats.additions)").foregroundStyle(theme.colors.add)
            }
            if stats.deletions > 0 {
                Text("−\(stats.deletions)").foregroundStyle(theme.colors.del)
            }
        }
        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.additions) additions, \(stats.deletions) deletions")
    }
}

#Preview("With actions") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    DiffHeader(
        file: "src/components/CommitGraph.tsx",
        status: .modified,
        stats: DiffStats(hunks: DiffHunk.previewSamples),
        viewMode: $mode,
        onOpenInEditor: {},
        onClose: {}
    )
    .frame(width: 720)
    .appTheme(theme)
}

#Preview("No actions") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .split
    DiffHeader(
        file: "src/components/CommitGraph.tsx",
        viewMode: $mode,
        onOpenInEditor: nil,
        onClose: nil
    )
    .frame(width: 720)
    .appTheme(theme)
}
