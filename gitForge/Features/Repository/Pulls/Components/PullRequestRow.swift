import SwiftUI
import AppKit

/// Where a row sits: on its own (a repository's list), or inside its repo's
/// card in Team and Mine, which rounds the card's outer corners and draws a
/// rule between rows.
enum PullRowPlacement: Equatable {
    case standalone
    case first, middle, last, only

    var isInCard: Bool { self != .standalone }
}

/// The shortcuts a row offers on hover and in its context menu: each only
/// asks, and the detail opens the panel or sheet its header's button opens
/// (`PullQuickAction`). `nil` leaves one out.
struct PullRowActions {
    var approve: (() -> Void)? = nil
    var merge: (() -> Void)? = nil

    static let none = PullRowActions()

    var isEmpty: Bool { approve == nil && merge == nil }
}

/// One pull request in a list: a rail in its verdict's colour; number,
/// verdict and date; title; author and branches. On hover (or selected) the
/// date gives way to the row's shortcuts: Approve, Merge (when it's ready)
/// and Open in browser.
struct PullRequestRow: View {
    let pullRequest: PullRequest
    let hostLabel: String?
    /// How the host writes the number (`!482` on GitLab); `#482` by default.
    var reference: String? = nil
    let ci: CIStatus?
    let isSelected: Bool
    var placement: PullRowPlacement = .standalone
    var actions: PullRowActions = .none
    /// Whether hovering shows the shortcuts; off where another control holds
    /// that corner (the × of an Other). The context menu keeps them.
    var offersShortcuts = true
    /// How far from the row's trailing edge the first line stops, for a
    /// control laid over that corner (the × of an Other in Reviews). Within
    /// the row's own padding it changes nothing.
    var firstLineTrailingClearance: CGFloat = 0
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @State private var hovering = false
    /// The row's width: in the narrow column Merge drops its word.
    @State private var width: CGFloat = 0

    var body: some View {
        Button(action: onSelect) {
            content
                .padding(.leading, Self.leadingPadding)
                .padding(.trailing, Self.horizontalPadding)
                .padding(.vertical, Spacing.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlight)
                .overlay(alignment: .leading) { rail }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions { accessibilityShortcuts }
        .background(cardBackground)
        .overlay(alignment: .top) { divider }
        .overlay(alignment: .topTrailing) { shortcuts }
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contextMenu { menu }
    }

    // MARK: Lines

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack(spacing: Spacing.s6) {
                Text(verbatim: reference ?? "#\(pullRequest.number)")
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize()
                if let hostLabel {
                    Text(hostLabel)
                        .textRole(.caption, weight: .semibold)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Spacing.s6)
                        .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
                }
                stateChip
                Spacer(minLength: Spacing.s4)
                trailingInfo
            }
            .frame(minHeight: 18)
            .padding(.trailing, max(0, firstLineTrailingClearance - Self.horizontalPadding))
            Text(pullRequest.title)
                .textRole(.body, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            byline
        }
    }

    /// The verdict for an open one; the state pill for a draft, a merged or
    /// a closed one.
    @ViewBuilder
    private var stateChip: some View {
        if pullRequest.state != .open {
            PullRequestStatePill(state: pullRequest.state, compact: true)
        } else if let status = pullRequest.listStatus {
            PullStatusChip(status: status)
        }
    }

    /// CI (when the host gave no verdict) and the date; hidden, keeping its
    /// room, while the shortcuts are over it.
    private var trailingInfo: some View {
        ZStack(alignment: .trailing) {
            if hasShortcuts {
                // Holds the shortcuts' room, so the line never runs under them.
                shortcutButtons.hidden().frame(height: 18)
            }
            HStack(spacing: Spacing.s6) {
                if let ci, pullRequest.listStatus == nil {
                    CIStateGlyph(ci.state, size: 11)
                        .help("CI \(ci.label)")
                }
                if let updated = pullRequest.updatedAt {
                    Text(preferences.dateDisplayMode.format(updated))
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .opacity(showsShortcuts ? 0 : 1)
        }
    }

    /// Author, then source → target branch.
    private var byline: some View {
        HStack(spacing: Spacing.s6) {
            if let author = pullRequest.authorLogin {
                Avatar(name: pullRequest.authorName ?? author, size: 16, colorSeed: author)
                Text(author)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(verbatim: "·").accessibilityHidden(true)
            }
            Text(pullRequest.sourceBranch)
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.colors.textQuaternary)
                .accessibilityHidden(true)
            Text(pullRequest.targetBranch)
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .lineLimit(1)
                .fixedSize()
        }
        .textRole(.callout)
        .foregroundStyle(theme.colors.textTertiary)
    }

    // MARK: Shortcuts

    private var hasShortcuts: Bool { offersShortcuts && (!actions.isEmpty || pullRequest.webURL != nil) }

    private var showsShortcuts: Bool { (hovering || isSelected) && hasShortcuts }

    private static let shortcutHeight: CGFloat = 22

    /// Below this width Merge shows its glyph alone, so the verdict and the
    /// shortcuts fit side by side (Team and Mine's 320 pt column).
    private static let compactShortcutsWidth: CGFloat = 340

    private var compactShortcuts: Bool { width > 0 && width < Self.compactShortcutsWidth }

    private var shortcutButtons: some View {
        HStack(spacing: Spacing.s4) {
            if let approve = actions.approve {
                RowShortcutButton(symbol: "checkmark", help: String(localized: "Approve…"), action: approve)
            }
            if let merge = actions.merge {
                RowShortcutButton(symbol: "arrow.triangle.merge",
                                  title: compactShortcuts ? nil : String(localized: "Merge"),
                                  tint: theme.colors.ok, tintSoft: theme.colors.okSoft,
                                  help: String(localized: "Merge…"), action: merge)
            }
            if let url = pullRequest.webURL {
                RowShortcutButton(symbol: "arrow.up.right", help: String(localized: "Open in browser")) {
                    ExternalURL.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private var shortcuts: some View {
        if showsShortcuts {
            shortcutButtons
                // Level with the first line, centred on it.
                .padding(.top, Spacing.s8 + (18 - Self.shortcutHeight) / 2)
                .padding(.trailing, Self.horizontalPadding - Spacing.s2)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let approve = actions.approve {
            Button("Approve…", action: approve)
        }
        if let merge = actions.merge {
            Button("Merge…", action: merge)
        }
        if !actions.isEmpty, pullRequest.webURL != nil {
            Divider()
        }
        if let url = pullRequest.webURL {
            Button("Open in browser") { ExternalURL.open(url) }
            Button("Copy link") {
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }

    @ViewBuilder
    private var accessibilityShortcuts: some View {
        if let approve = actions.approve {
            Button("Approve…", action: approve)
        }
        if let merge = actions.merge {
            Button("Merge…", action: merge)
        }
        if let url = pullRequest.webURL {
            Button("Open in browser") { ExternalURL.open(url) }
        }
    }

    // MARK: Chrome

    private static let horizontalPadding = Spacing.s12
    /// Room for the rail on the leading edge.
    private static let leadingPadding = Spacing.s16

    /// The verdict's colour down the leading edge: merged in the accent,
    /// closed in red, drafts and silent hosts in grey.
    private var rail: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(railColor)
            .frame(width: 3)
            .padding(.vertical, Spacing.s8)
            .padding(.leading, Spacing.s6)
            .accessibilityHidden(true)
    }

    private var railColor: Color {
        switch pullRequest.state {
        case .open: pullRequest.listStatus == nil ? theme.colors.textQuaternary.opacity(0.5)
                                                  : theme.colors.tone(pullRequest.statusTone).fg
        case .draft: theme.colors.textQuaternary.opacity(0.5)
        case .merged: theme.colors.accent
        case .closed: theme.colors.del
        }
    }

    /// Selection and hover; inset inside a card, so its fill shows around it.
    private var highlight: some View {
        RoundedRectangle(cornerRadius: placement.isInCard ? Radius.row : Radius.control)
            .fill(highlightFill)
            .padding(placement.isInCard ? Spacing.s2 : 0)
    }

    private var highlightFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }

    @ViewBuilder
    private var cardBackground: some View {
        if placement.isInCard {
            UnevenRoundedRectangle(cornerRadii: cardRadii).fill(theme.colors.fillHover)
        }
    }

    private var cardRadii: RectangleCornerRadii {
        let r = Radius.card - 2
        switch placement {
        case .standalone, .middle: return .init()
        case .first: return .init(topLeading: r, topTrailing: r)
        case .last: return .init(bottomLeading: r, bottomTrailing: r)
        case .only: return .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
    }

    /// The rule between two rows of a card.
    @ViewBuilder
    private var divider: some View {
        if placement == .middle || placement == .last {
            Rectangle()
                .fill(theme.colors.separator)
                .frame(height: 1)
                .padding(.leading, Self.leadingPadding)
                .padding(.trailing, Self.horizontalPadding)
                .accessibilityHidden(true)
        }
    }
}

/// A row's shortcut: a small icon button, or a tinted one with its word for
/// the one that moves the pull request forward (Merge).
private struct RowShortcutButton: View {
    let symbol: String
    var title: String? = nil
    var tint: Color? = nil
    var tintSoft: Color? = nil
    let help: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.controlSmall)
        Button(action: action) {
            HStack(spacing: Spacing.s4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                if let title {
                    Text(title)
                        .textRole(.caption, weight: .semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(tint ?? (hovering ? theme.colors.textPrimary : theme.colors.textSecondary))
            .padding(.horizontal, title == nil ? 0 : Spacing.s8)
            .frame(minWidth: 22, minHeight: 22, maxHeight: 22)
            .background(shape.fill(background))
            .overlay(shape.strokeBorder(tint?.opacity(0.35) ?? theme.colors.strokeControl, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if let tintSoft, let tint { return hovering ? tint.opacity(0.26) : tintSoft }
        return hovering ? theme.colors.fillControl : theme.colors.bgContent.opacity(0.6)
    }
}

#Preview("Standalone") {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 2) {
        ForEach(PullRequest.rowPreviewSamples) { pr in
            PullRequestRow(pullRequest: pr, hostLabel: nil, reference: "!\(pr.number)",
                           ci: nil, isSelected: pr.number == 3957,
                           actions: PullRowActions(approve: {}, merge: pr.isReadyToMerge ? {} : nil),
                           onSelect: {})
        }
    }
    .padding(Spacing.s8)
    .frame(width: 380)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}

extension PullRequest {
    /// One row per verdict, for the previews.
    static var rowPreviewSamples: [PullRequest] {
        let kinds: [(Int, PullRequest.State, PullListStatus.Kind?, String)] = [
            (3957, .open, .blocked, "Identity documents: detail sheet, editing and removal"),
            (3958, .open, .ready, "Identity documents: add passport and driving licence"),
            (3956, .open, .failing, "Identity documents: list in personal data"),
            (3955, .open, .needsApproval, "Plate tests: translated texts independent of the language"),
            (3885, .draft, nil, "Draft: SwiftUI migration up to the pending screens"),
            (3870, .merged, nil, "Release 1.20.2"),
        ]
        return kinds.map { number, state, kind, title in
            PullRequest(id: "\(number)", number: number, title: title, state: state, authorLogin: "jdoe",
                        authorAvatarURL: nil, sourceBranch: "feature/APP-\(number)", targetBranch: "develop",
                        webURL: URL(string: "https://gitlab.example.test/apps/app/-/merge_requests/\(number)"),
                        createdAt: nil, updatedAt: .now.addingTimeInterval(-Double(number % 7 + 1) * 3_600),
                        authorName: "Jane Doe", listStatus: kind.map { PullListStatus(kind: $0) })
        }
    }
}
