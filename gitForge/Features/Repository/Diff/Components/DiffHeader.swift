import SwiftUI

/// Action handlers are optional so callers can hide the buttons in contexts
/// where they don't apply (history-mode diffs have no editor target; only
/// History needs to collapse the pane).
struct DiffHeader: View {
    let file: String?
    @Binding var viewMode: DiffPane.ViewMode
    let onOpenInEditor: (() -> Void)?
    let onClose: (() -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                GFIcon(kind: .diff, size: 12, stroke: theme.palette.fg1)
                Text(file ?? "—")
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            SegmentedControl<DiffPane.ViewMode>(
                [(.unified, "Unified"), (.split, "Split")],
                selection: $viewMode
            )
            if let onOpenInEditor {
                IconButton(.ext, accessibilityLabel: "Open in editor", action: onOpenInEditor)
                    .help("Open in editor")
            }
            if let onClose {
                IconButton(.x, accessibilityLabel: "Hide diff pane", action: onClose)
                    .help("Hide diff pane")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .frame(height: 34)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.line)
                .frame(height: DesignTokens.Stroke.regular)
        }
    }
}

#Preview("With actions") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    DiffHeader(
        file: "src/components/CommitGraph.tsx",
        viewMode: $mode,
        onOpenInEditor: {},
        onClose: {}
    )
    .frame(width: 720)
    .background(theme.palette.bg2)
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
    .background(theme.palette.bg2)
    .appTheme(theme)
}
