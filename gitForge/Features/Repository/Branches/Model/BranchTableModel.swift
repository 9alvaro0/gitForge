import CoreGraphics

/// Which refs the Branches & Tags table lists.
nonisolated enum BranchScope: String, CaseIterable, Identifiable, Sendable {
    case local, remote, tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local"
        case .remote: "Remote"
        case .tags: "Tags"
        }
    }

    func includes(_ ref: GitRef) -> Bool {
        switch self {
        case .local: ref.isLocalBranch
        case .remote: ref.isRemoteBranch
        case .tags: ref.isTag
        }
    }
}

/// Colour of a branch's lane glyph in the table. Only HEAD and the pinned
/// trunks get a lane colour: those match the graph by rule (spec §4.5).
/// Any other branch's graph colour depends on the layout, so the table
/// shows it neutral rather than guess a colour the graph won't use.
nonisolated enum BranchGlyphColor: Equatable, Sendable {
    case accent
    case lane(LaneColors.Lane)
    case neutral

    static func of(_ ref: GitRef, currentBranch: String?) -> BranchGlyphColor {
        if ref.isLocalBranch && ref.name == currentBranch { return .accent }
        guard !ref.isTag else { return .neutral }
        switch ref.displayName {
        case "main", "master": return .lane(.lane0)
        case "develop": return .lane(.lane3)
        default: return .neutral
        }
    }
}

/// Column widths for the Branches & Tags table. The name column takes what
/// is left; the last-commit subject shrinks first and hides below 120 pt so
/// names stay readable in a narrow window.
nonisolated struct BranchTableLayout: Equatable, Sendable {
    let upstream: CGFloat
    let commit: CGFloat
    let subject: CGFloat
    let updated: CGFloat

    static let upstreamWidth: CGFloat = 110
    static let commitWidth: CGFloat = 72
    static let updatedWidth: CGFloat = 84
    static let maxSubject: CGFloat = 250
    static let minSubject: CGFloat = 160
    static let minName: CGFloat = 240
    /// Row padding plus the list's outer margin, both sides.
    static let chrome: CGFloat = 36

    init(width: CGFloat, scope: BranchScope) {
        upstream = scope == .local ? Self.upstreamWidth : 0
        commit = scope == .tags ? Self.commitWidth : 0
        updated = Self.updatedWidth
        let room = width - Self.chrome - Self.minName - upstream - commit - updated
        let fitted = min(Self.maxSubject, max(0, room))
        subject = fitted >= Self.minSubject ? fitted : 0
    }
}
