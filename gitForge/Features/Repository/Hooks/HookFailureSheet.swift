import AppKit
import SwiftUI

/// What a local git hook printed when it stopped a commit or a `--continue`:
/// the full output, monospaced, scrollable and selectable, with Retry and —
/// for a plain commit — "Commit without hooks" (`--no-verify`) (#58).
struct HookFailureSheet: View {
    let failure: HookFailure
    let onRetry: () -> Void
    let onCommitWithoutHooks: () -> Void
    let onClose: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Label {
                Text(failure.title).textRole(.title)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.warn)
            }
            Text(failure.message)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            output
            if failure.canSkipHooks {
                Label {
                    Text("“Commit without hooks” runs git commit --no-verify: pre-commit and commit-msg don’t run, so the checks they enforce are skipped for this commit.")
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            HStack(spacing: Spacing.s8) {
                GFButton(title: String(localized: "Copy output"), systemImage: "doc.on.doc",
                         disabled: failure.output.isEmpty) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(failure.output, forType: .string)
                }
                Spacer()
                GFButton(title: String(localized: "Close"), shortcut: .cancelAction, action: onClose)
                if failure.canSkipHooks {
                    GFButton(title: String(localized: "Commit without hooks"), style: .destructive,
                             action: onCommitWithoutHooks)
                }
                GFButton(title: String(localized: "Retry"), systemImage: "arrow.clockwise", style: .primary,
                         shortcut: .defaultAction, action: onRetry)
            }
        }
        .padding(Spacing.s16)
        .frame(width: 620)
    }

    private var output: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return ScrollView([.vertical, .horizontal]) {
            MonoText(failure.output.isEmpty ? String(localized: "The hook printed nothing.") : failure.output,
                     dim: failure.output.isEmpty, color: failure.output.isEmpty ? nil : theme.colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Spacing.s8)
        }
        .frame(minHeight: 160, idealHeight: 280, maxHeight: 360)
        .background(shape.fill(theme.colors.bgCode))
        .overlay(shape.strokeBorder(theme.colors.strokeControl, lineWidth: 1))
        .accessibilityLabel("Hook output")
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HookFailureSheet(
        failure: HookFailure(operation: .commit(pushAfterwards: false, confirmedAmendOfPublished: false),
                             hookName: "pre-commit",
                             output: "eslint: 2 problems\nsrc/app.js:12:3  error  'x' is never used  no-unused-vars\nsrc/app.js:40:1  error  Unexpected var  no-var"),
        onRetry: {}, onCommitWithoutHooks: {}, onClose: {}
    )
    .appTheme(theme)
}
