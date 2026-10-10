import SwiftUI

/// Every CI job of the PR's head commit: state glyph, name and where it
/// runs, why it failed, state word, duration and a link to the logs.
struct PullRequestChecksTab: View {
    let checks: [CICheck]
    let loading: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        if checks.isEmpty {
            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(icon: .check, title: "No checks",
                           subtitle: "No CI has reported on the latest commit of this pull request.")
            }
        } else {
            VStack(spacing: 0) {
                ForEach(sorted) { check in
                    row(check)
                    if check.id != sorted.last?.id {
                        Rectangle().fill(theme.colors.separator).frame(height: 1)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgContent))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(theme.colors.separator, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        }
    }

    /// Failures first, then running, queued, passed, the rest.
    private var sorted: [CICheck] {
        func rank(_ state: CICheck.State) -> Int {
            switch state {
            case .failed: 0
            case .running: 1
            case .queued: 2
            case .passed: 3
            case .canceled: 4
            case .skipped: 5
            }
        }
        return checks.enumerated().sorted { (rank($0.element.state), $0.offset) < (rank($1.element.state), $1.offset) }.map(\.element)
    }

    private func row(_ check: CICheck) -> some View {
        let glyph = CIStateGlyph(check.state, size: 16)
        return HStack(spacing: Spacing.s12) {
            glyph
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                    Text(check.name)
                        .textRole(.body, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if let context = check.context {
                        Text(context)
                            .textRole(.callout)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                if let message = check.failureMessage, !message.isEmpty {
                    Text(message)
                        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                        .foregroundStyle(theme.colors.del)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(check.state.label)
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(glyph.color)
                .frame(width: 72, alignment: .leading)
            Text(check.duration.map(Self.format) ?? "—")
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 56, alignment: .trailing)
            if let url = check.webURL {
                Button("Logs") { ExternalURL.open(url) }
                    .buttonStyle(.link)
                    .font(AppFont.font(.callout))
                    .frame(width: 40, alignment: .trailing)
                    .help("Open the logs on the host")
            } else {
                Spacer().frame(width: 40)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .frame(minHeight: 44)
        .background(check.state == .failed ? theme.colors.delSoft.opacity(0.4) : .clear)
        .accessibilityElement(children: .combine)
    }

    /// "4m 12s", "38s", "1h 2m".
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(String(format: "%02d", total % 60))s" }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }
}
