import SwiftUI
import AppKit

/// One PR in the list: number, host, CI; title; branch · author · date.
struct PullRequestRow: View {
    let pullRequest: PullRequest
    let hostLabel: String?
    /// How the host writes the number (`!482` on GitLab); `#482` by default.
    var reference: String? = nil
    let ci: CIStatus?
    let isSelected: Bool
    /// How far from the row's trailing edge the first line stops, for a
    /// control laid over that corner (the × of an Other in Reviews). Within
    /// the row's own padding it changes nothing.
    var firstLineTrailingClearance: CGFloat = 0
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(spacing: Spacing.s8) {
                    Text(verbatim: reference ?? "#\(pullRequest.number)")
                        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                        .foregroundStyle(theme.colors.textTertiary)
                    if let hostLabel {
                        Text(hostLabel)
                            .textRole(.caption, weight: .semibold)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, Spacing.s6)
                            .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
                    }
                    if pullRequest.state != .open {
                        PullRequestStatePill(state: pullRequest.state)
                    }
                    Spacer(minLength: 0)
                    if let ci {
                        CIBadge(status: ci)
                    }
                }
                .padding(.trailing, max(0, firstLineTrailingClearance - Self.horizontalPadding))
                Text(pullRequest.title)
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: Spacing.s6) {
                    Text(pullRequest.sourceBranch)
                        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let author = pullRequest.authorLogin {
                        Text("·")
                        Text(author).lineLimit(1)
                    }
                    if let updated = pullRequest.updatedAt {
                        Text("·")
                        Text(preferences.dateDisplayMode.format(updated)).lineLimit(1).fixedSize()
                    }
                }
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if let url = pullRequest.webURL {
                Button("Open in browser") { ExternalURL.open(url) }
                Button("Copy link") {
                    NSPasteboard.general.declareTypes([.string], owner: nil)
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
    }

    private static let horizontalPadding = Spacing.s12

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 2) {
        ForEach(PullRequest.previewSamples) { pr in
            PullRequestRow(pullRequest: pr, hostLabel: "GitHub",
                           ci: CIStatus(state: .failure, description: nil, webURL: nil),
                           isSelected: pr.id == PullRequest.previewSamples.first?.id, onSelect: {})
        }
    }
    .padding(Spacing.s8)
    .frame(width: 380)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
