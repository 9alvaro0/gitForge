import SwiftUI

/// Branch / tag chips for a single commit row. Up to two chips when refs ≤ 2,
/// otherwise the first chip plus a "+N" overflow pill that opens a popover
/// with the rest. Local branch chips are draggable and act as drop targets
/// (chip→chip merge/rebase). Remote / tag chips render plain — drag is gated
/// to local branches in this version.
struct CommitRowChips: View {
    let commitSha: String
    let refs: [GitRef]
    let currentBranch: String?
    /// Receives drops landing on a local-branch chip (merge / rebase).
    /// `nil` disables the drag/drop hooks entirely on this row.
    let onBranchDrop: ((DraggedBranch, BranchDropContext) -> Void)?
    /// Caps each chip's name; `nil` leaves it unbounded.
    var maxNameWidth: CGFloat? = nil
    /// Chips shown before the rest fold into "+N" (at least 1).
    var maxVisible: Int = 2
    /// Lane colour of this commit in the graph; branch chips take it as a
    /// tint so each chip matches the line it labels.
    var laneColor: Color? = nil
    /// How each remote chip is named and bordered (§4.4): the prefix when two remotes share a
    /// branch name, a dashed border when it is away from its local branch.
    var chips: HistoryRefChips = .empty
    /// This commit only exists on the server: its remote chips get a dashed border.
    var isGhost = false

    @Environment(\.appTheme) private var theme
    @Environment(\.branchDropTracker) private var dropTracker
    @State private var showHiddenRefs = false

    var body: some View {
        // Filter + sort once per body; the visible / hidden / overflow
        // helpers each re-sorted the refs before.
        let split = splitRefs
        HStack(spacing: Spacing.s4) {
            ForEach(split.visible) { ref in
                chipView(for: ref)
            }
            if !split.hidden.isEmpty {
                overflowPill(hidden: split.hidden)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chipView(for ref: GitRef) -> some View {
        let isCurrent = ref.isLocalBranch && ref.name == currentBranch
        let chip = branchChip(for: ref, maxNameWidth: maxNameWidth)
        if ref.isLocalBranch, let onBranchDrop {
            chip
                // The payload closure runs when the drag starts: record the
                // source for the HUD's graph preview.
                .draggable({
                    dropTracker?.beginDrag(name: ref.name, sha: commitSha)
                    return DraggedBranch(name: ref.name, isCurrent: isCurrent, isLocal: true, sourceSha: commitSha)
                }()) {
                    BranchDragGhost(name: ref.displayName, isCurrent: isCurrent)
                        .appTheme(theme)
                }
                .modifier(ChipDropModifier(
                    targetBranchName: ref.name,
                    targetSha: commitSha,
                    onDrop: { dropped in
                        onBranchDrop(dropped, .onBranch(targetBranchName: ref.name, targetSha: commitSha))
                    }
                ))
        } else {
            chip
        }
    }

    private func branchChip(for ref: GitRef, maxNameWidth: CGFloat?) -> BranchChip {
        BranchChip(
            name: chips.label(for: ref),
            current: ref.isLocalBranch && ref.name == currentBranch,
            remote: ref.isRemoteBranch,
            tag: ref.isTag,
            hasRemoteCounterpart: hasRemoteCounterpart(for: ref),
            maxNameWidth: maxNameWidth,
            laneColor: laneColor,
            ahead: ref.ahead ?? 0,
            behind: ref.behind ?? 0,
            dashedBorder: chips.isDashed(ref, onGhost: isGhost)
        )
    }

    /// Names of local branches present on this commit. Remote-tracking refs
    /// whose `displayName` matches one of these are deduplicated — the local
    /// chip gets the cloud icon trailing it instead of producing a second
    /// chip with the same name.
    private var localBranchNames: Set<String> {
        Set(refs.filter(\.isLocalBranch).map(\.displayName))
    }

    private func hasRemoteCounterpart(for ref: GitRef) -> Bool {
        guard ref.isLocalBranch else { return false }
        return refs.contains { $0.isRemoteBranch && $0.displayName == ref.displayName }
    }

    private var sortedRefs: [GitRef] {
        let names = localBranchNames
        return refs
            .filter { ref in
                // Drop remote-tracking ref if a local branch with the same name
                // is also on this commit — they collapse into a single chip.
                !(ref.isRemoteBranch && names.contains(ref.displayName))
            }
            .sorted { a, b in
                let aCurrent = a.isLocalBranch && a.name == currentBranch
                let bCurrent = b.isLocalBranch && b.name == currentBranch
                if aCurrent != bCurrent { return aCurrent }
                let aWeight = Self.refWeight(a)
                let bWeight = Self.refWeight(b)
                if aWeight != bWeight { return aWeight < bWeight }
                // Remotes sharing a branch name (shown with their prefix) fall back to the full name.
                if a.displayName != b.displayName { return a.displayName < b.displayName }
                return a.name < b.name
            }
    }

    private static func refWeight(_ ref: GitRef) -> Int {
        if ref.isLocalBranch  { return 0 }
        if ref.isTag          { return 1 }
        if ref.isRemoteBranch { return 2 }
        return 3
    }

    private var splitRefs: (visible: [GitRef], hidden: [GitRef]) {
        let sorted = sortedRefs
        let limit = max(1, maxVisible)
        guard sorted.count > limit else { return (sorted, []) }
        let shown = max(1, limit - 1)
        return (Array(sorted.prefix(shown)), Array(sorted.dropFirst(shown)))
    }

    @ViewBuilder
    private func overflowPill(hidden: [GitRef]) -> some View {
        let count = hidden.count
        Button {
            showHiddenRefs.toggle()
        } label: {
            Text("+\(count)")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, Spacing.s6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: Radius.chip).fill(theme.colors.fillControl))
                // Open: an extra layer over the rest fill, so it reads stronger.
                .background(RoundedRectangle(cornerRadius: Radius.chip)
                    .fill(showHiddenRefs ? theme.colors.fillHover : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.chip)
                        .stroke(theme.colors.strokeControl, lineWidth: 1)
                )
                .contentShape(.rect(cornerRadius: Radius.chip))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { showHiddenRefs = true }
        }
        .popover(isPresented: $showHiddenRefs, arrowEdge: .bottom) {
            hiddenRefsPopover(hidden)
        }
    }

    private func hiddenRefsPopover(_ hiddenRefs: [GitRef]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text("\(hiddenRefs.count) more")
                .textRole(.caption, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(theme.colors.textTertiary)
            ForEach(hiddenRefs) { ref in
                branchChip(for: ref, maxNameWidth: nil)
            }
        }
        .padding(Spacing.s12)
        .background(theme.colors.bgContent)
        .appTheme(theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let refs = [
        // a1: HEAD, ahead and behind its upstream.
        GitRef(name: "main", kind: .localBranch, targetSha: "a1", isHead: true, upstream: "origin/main", ahead: 2, behind: 1),
        // b2: the upstream away from its local branch (dashed), and a fork's branch of the same name (both prefixed).
        GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "b2", isHead: false),
        GitRef(name: "fork/main", kind: .remoteBranch(remote: "fork"), targetSha: "b2", isHead: false),
        // c3: a local branch behind its upstream; d4: that upstream, on a ghost commit.
        GitRef(name: "feature/chips", kind: .localBranch, targetSha: "c3", isHead: false,
               upstream: "origin/feature/chips", ahead: 0, behind: 3),
        GitRef(name: "origin/feature/chips", kind: .remoteBranch(remote: "origin"), targetSha: "d4", isHead: false),
        GitRef(name: "v0.1.0", kind: .tag, targetSha: "c3", isHead: false),
    ]
    let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
    VStack(alignment: .leading, spacing: 8) {
        ForEach(["a1", "b2", "c3", "d4"], id: \.self) { sha in
            CommitRowChips(
                commitSha: sha,
                refs: chips.refs(on: sha),
                currentBranch: "main",
                onBranchDrop: nil,
                laneColor: LaneColors.color(.lane(.lane2), dark: true, accent: .accentColor),
                chips: chips,
                isGhost: sha == "d4"
            )
        }
    }
    .padding()
    .frame(width: 320)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
