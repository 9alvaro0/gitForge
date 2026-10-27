import SwiftUI

/// A repo's heading in Team and Mine: its mark, its name over the group or
/// owner it's in, "Not cloned" when it isn't on this Mac, and how many of
/// its rows are in each tone. A click folds or unfolds its rows. Pinned
/// while its rows scroll under it. A followed repo's, and the open
/// repository's when it isn't followed, has "Hide" in its context menu (R3
/// Ruling 15, U1 Ruling 8).
struct ReviewGroupHeader: View {
    let repo: ReviewRepo
    /// Its rows, for the tone summary.
    var pulls: [PullRequest] = []
    var isCollapsed = false
    /// Folds or unfolds its rows; `nil` shows no chevron.
    var onToggle: (() -> Void)? = nil
    /// Hides the repo from Team and Mine; `nil` offers nothing (a repo opened
    /// from a search, which nobody follows).
    var onHide: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button { onToggle?() } label: {
            HStack(spacing: Spacing.s8) {
                // Its room even with nothing to fold, so every mark lines up.
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? theme.colors.textSecondary : theme.colors.textQuaternary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)
                    .opacity(onToggle == nil ? 0 : 1)
                    .accessibilityHidden(true)
                RepoMonogram(repo: repo.host)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.s6) {
                        Text(verbatim: repo.host.repo)
                            .textRole(.body, weight: .semibold)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if repo.localURL == nil {
                            Text("Not cloned")
                                .textRole(.caption, weight: .semibold)
                                .foregroundStyle(theme.colors.textTertiary)
                                .padding(.horizontal, Spacing.s6)
                                .frame(height: 16)
                                .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
                                .fixedSize()
                        }
                    }
                    Text(verbatim: repo.host.owner)
                        .textRole(.caption, weight: .regular)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        // A nested GitLab group keeps both ends.
                        .truncationMode(.middle)
                }
                Spacer(minLength: Spacing.s4)
                PullToneSummary(counts: PullStatusTone.summary(of: pulls))
            }
            .contentShape(.rect)
        }
        // Never `.disabled`, even with nothing to fold: that would dim a repo
        // whose rows couldn't be read, and take its "Hide" away.
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .reviewSectionHeader()
        .help(Text(verbatim: "\(repo.host.host)/\(repo.host.slug)"))
        .modifier(HideMenu(onHide: onHide))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(onToggle == nil ? Text(verbatim: "") : isCollapsed ? Text("Collapsed") : Text("Expanded"))
    }

    /// The hiding as the context menu, only with `onHide`: without it there's
    /// no menu at all, rather than an empty one.
    private struct HideMenu: ViewModifier {
        let onHide: (() -> Void)?

        func body(content: Content) -> some View {
            if let onHide {
                content.contextMenu { Button(String(localized: "Hide from Pull requests"), action: onHide) }
            } else {
                content
            }
        }
    }
}

/// A heading's count per tone: a dot in the tone's colour and the number,
/// what needs attention first.
struct PullToneSummary: View {
    let counts: [PullToneCount]

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s8) {
            ForEach(counts, id: \.tone) { entry in
                HStack(spacing: Spacing.s4) {
                    Circle()
                        .fill(theme.colors.tone(entry.tone).fg)
                        .frame(width: 7, height: 7)
                    Text(verbatim: "\(entry.count)")
                        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .help(Self.help(entry))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.map(Self.help).joined(separator: ", "))
    }

    private static func help(_ entry: PullToneCount) -> String {
        switch entry.tone {
        case .ok: String(localized: "Ready to merge: \(entry.count)")
        case .info: String(localized: "Checks running: \(entry.count)")
        case .warn: String(localized: "Waiting on review: \(entry.count)")
        case .danger: String(localized: "Blocked or failing: \(entry.count)")
        case .neutral: String(localized: "Drafts or no status: \(entry.count)")
        }
    }
}

/// The heading over the pull requests opened from a link that aren't rows of
/// the followed repos (R2 Ruling 9), with a repo's heading's look.
struct ReviewOthersHeader: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text("Others")
            .textRole(.callout, weight: .semibold)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
            .reviewSectionHeader()
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// What every heading of the inbox shares: its inset, a little closer
    /// to its own rows than to the group above, and the list's background,
    /// so the rows scroll under it while it's pinned.
    func reviewSectionHeader() -> some View {
        modifier(ReviewSectionHeaderChrome())
    }
}

private struct ReviewSectionHeaderChrome: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s8)
            .padding(.top, Spacing.s16)
            .padding(.bottom, Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.bgContent)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    VStack(spacing: 0) {
        ForEach(["apps/payments/android/payments-app", "apps/platform/infra-modules"], id: \.self) { path in
            ReviewGroupHeader(repo: ReviewRepo(host: RemoteHost.make(fullName: path, on: instance)!,
                                               accountId: UUID(), sources: [.activity], lastActivity: nil,
                                               cloneURL: "https://gitlab.example.test/\(path).git",
                                               localURL: path.hasSuffix("-app") ? URL(fileURLWithPath: "/tmp/payments-app") : nil),
                              pulls: PullRequest.rowPreviewSamples, isCollapsed: !path.hasSuffix("-app"),
                              onToggle: {}, onHide: {})
        }
    }
    .frame(width: 320)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
