import SwiftUI

/// Read-only preview of the file as "Mark resolved" would write it: lines
/// from a hunk carry their side's tag and tint, unpicked hunks a dashed
/// placeholder.
struct ConflictResultPanel: View {
    let lines: [ConflictResultLine]

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s6) {
                Text("Result")
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.textQuaternary)
                Text("· read only · written when you mark the file resolved")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 30)
            .background(theme.colors.bgElevated)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.colors.separator).frame(height: 1)
            }
            ScrollView([.vertical]) {
                LazyVStack(spacing: 0) {
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.vertical, Spacing.s4)
            }
            .background(theme.colors.bgCode)
        }
    }

    @ViewBuilder
    private func row(_ line: ConflictResultLine) -> some View {
        switch line.kind {
        case .text:
            ConflictCodeLine(number: line.number, text: line.text, markWidth: 64)
        case .ours:
            ConflictCodeLine(number: line.number, text: line.text, tint: theme.colors.infoSoft.opacity(0.6),
                             mark: ConflictSide.ours.label, markColor: theme.colors.info, markWidth: 64)
        case .theirs:
            ConflictCodeLine(number: line.number, text: line.text, tint: theme.colors.warnSoft.opacity(0.6),
                             mark: ConflictSide.theirs.label, markColor: theme.colors.warn, markWidth: 64)
        case .unresolved(let hunkIndex):
            HStack(spacing: Spacing.s8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                Text("Hunk \(hunkIndex + 1) unresolved · pick a side above")
                    .textRole(.callout)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.warn)
            .padding(.horizontal, Spacing.s12)
            .frame(height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(theme.colors.warn.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
            .padding(.leading, 36 + Spacing.s8 + 64)
            .padding(.trailing, Spacing.s12)
            .padding(.vertical, Spacing.s2)
        }
    }
}
