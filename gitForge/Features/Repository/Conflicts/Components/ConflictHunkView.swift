import SwiftUI

/// A conflict hunk. Unpicked: ours | theirs side by side with the pick
/// buttons. Picked: folded into a one-line summary with "Change".
struct ConflictHunkView: View {
    let hunk: ConflictHunk
    let index: Int
    let pick: ConflictHunk.Pick?
    let isFocused: Bool
    let onPick: (ConflictHunk.Pick) -> Void
    let onClear: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let pick {
                folded(pick)
            } else {
                open
            }
        }
        .overlay {
            if isFocused {
                Rectangle().strokeBorder(theme.colors.accent, lineWidth: 1.5)
            }
        }
    }

    // MARK: Folded

    private func folded(_ pick: ConflictHunk.Pick) -> some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.colors.ok)
            Text("Hunk \(index + 1)")
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.ok)
            Text(Self.pickLabel(pick))
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 0)
            GFButton(title: "Change", size: .small, action: onClear)
                .help("Undo this pick")
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 34)
        .background(theme.colors.okSoft)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hunk \(index + 1), resolved with \(Self.pickLabel(pick))")
    }

    static func pickLabel(_ pick: ConflictHunk.Pick) -> String {
        switch pick {
        case .ours: "Ours"
        case .theirs: "Theirs"
        case .both: "Both · ours first"
        }
    }

    // MARK: Open

    private var open: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.colors.warn)
                Text("Hunk \(index + 1)")
                    .textRole(.callout, weight: .semibold)
                    .foregroundStyle(theme.colors.warn)
                Text("\(hunk.ours.count) vs \(hunk.theirs.count) lines")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 30)
            .background(theme.colors.fillHover)

            HStack(alignment: .top, spacing: 0) {
                side(.ours, lines: hunk.ours)
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                side(.theirs, lines: hunk.theirs)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s8) {
                ConflictSideButton(side: .ours, title: "Use ours") { onPick(.ours) }
                ConflictSideButton(side: .theirs, title: "Use theirs") { onPick(.theirs) }
                GFButton(title: "Both · ours first") { onPick(.both) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s8)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }

    private func side(_ side: ConflictSide, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text("No lines on this side")
                    .textRole(.callout)
                    .italic()
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, Spacing.s12)
                    .frame(minHeight: theme.density.metrics.diffLine)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                    ConflictCodeLine(
                        number: offset + 1,
                        text: line.hasSuffix("\r") ? String(line.dropLast()) : line,
                        tint: side.soft(theme.colors),
                        mark: "│",
                        markColor: side.color(theme.colors)
                    )
                }
            }
        }
        .padding(.vertical, Spacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side == .ours ? "Ours" : "Theirs"), \(lines.count) lines")
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ConflictHunkView(hunk: ConflictHunk.previewSamples[0], index: 0, pick: .both,
                         isFocused: false, onPick: { _ in }, onClear: {})
        ConflictHunkView(hunk: ConflictHunk.previewSamples[0], index: 1, pick: nil,
                         isFocused: true, onPick: { _ in }, onClear: {})
    }
    .frame(width: 820)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
