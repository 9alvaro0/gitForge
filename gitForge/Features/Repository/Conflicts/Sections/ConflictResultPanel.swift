import SwiftUI

/// The file as "Mark resolved" would write it. By default a preview built
/// from the picks (lines from a hunk carry their side's tag and tint,
/// unpicked hunks a dashed placeholder); "Edit" turns it into a text editor
/// whose content replaces the picks.
struct ConflictResultPanel: View {
    let lines: [ConflictResultLine]
    /// `nil` while resolving with picks.
    @Binding var manualText: String?
    let manualTextHasMarkers: Bool
    let onEdit: () -> Void
    let onDiscardEdits: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            if let manualText {
                TextEditor(text: Binding(get: { manualText }, set: { self.manualText = $0 }))
                    .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Spacing.s8)
                    .padding(.vertical, Spacing.s4)
                    .background(theme.colors.bgCode)
                    .accessibilityLabel("Result, editable")
            } else {
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
    }

    private var header: some View {
        HStack(spacing: Spacing.s6) {
            Text("Result")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textQuaternary)
            if manualText == nil {
                Text("· written when you mark the file resolved")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            } else if manualTextHasMarkers {
                Label("Conflict markers left — remove them to mark resolved", systemImage: "exclamationmark.triangle")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.warn)
            } else {
                Text("· edited by hand · replaces the picks")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer(minLength: 0)
            if manualText == nil {
                GFButton(title: "Edit", systemImage: "pencil", size: .small, action: onEdit)
                    .help("Write the result yourself, starting from the current picks")
            } else {
                GFButton(title: "Discard edits", style: .destructive, size: .small, action: onDiscardEdits)
                    .help("Go back to resolving with the picks")
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Spacing.s12)
        .frame(height: 34)
        .background(theme.colors.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
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
