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

    @Environment(\.appTheme) private var theme
    @State private var showHiddenRefs = false

    var body: some View {
        HStack(spacing: Spacing.s4) {
            ForEach(visibleRefs) { ref in
                chipView(for: ref)
            }
            if let extra = overflowCount {
                overflowPill(count: extra)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chipView(for ref: GitRef) -> some View {
        let isCurrent = ref.isLocalBranch && ref.name == currentBranch
        let chip = BranchChip(
            name: ref.displayName,
            current: isCurrent,
            remote: ref.isRemoteBranch,
            tag: ref.isTag,
            hasRemoteCounterpart: hasRemoteCounterpart(for: ref),
            maxNameWidth: maxNameWidth
        )
        if ref.isLocalBranch, let onBranchDrop {
            chip
                .draggable(DraggedBranch(
                    name: ref.name,
                    isCurrent: isCurrent,
                    isLocal: true,
                    sourceSha: commitSha
                )) {
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
                return a.displayName < b.displayName
            }
    }

    private static func refWeight(_ ref: GitRef) -> Int {
        if ref.isLocalBranch  { return 0 }
        if ref.isTag          { return 1 }
        if ref.isRemoteBranch { return 2 }
        return 3
    }

    private var visibleRefs: [GitRef] {
        let limit = max(1, maxVisible)
        return sortedRefs.count <= limit ? sortedRefs : Array(sortedRefs.prefix(max(1, limit - 1)))
    }

    private var hiddenRefs: [GitRef] {
        Array(sortedRefs.dropFirst(visibleRefs.count))
    }

    private var overflowCount: Int? {
        hiddenRefs.isEmpty ? nil : hiddenRefs.count
    }

    @ViewBuilder
    private func overflowPill(count: Int) -> some View {
        Button {
            showHiddenRefs.toggle()
        } label: {
            Text("+\(count)")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, Spacing.s6)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: Radius.chip)
                        .fill(showHiddenRefs ? theme.colors.fillHover : theme.colors.fillControl)
                )
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
            hiddenRefsPopover
        }
    }

    private var hiddenRefsPopover: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text("\(hiddenRefs.count) more")
                .textRole(.caption, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(theme.colors.textTertiary)
            ForEach(hiddenRefs) { ref in
                BranchChip(
                    name: ref.displayName,
                    current: ref.isLocalBranch && ref.name == currentBranch,
                    remote: ref.isRemoteBranch,
                    tag: ref.isTag,
                    hasRemoteCounterpart: hasRemoteCounterpart(for: ref)
                )
            }
        }
        .padding(Spacing.s12)
        .background(theme.colors.bgContent)
        .appTheme(theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 8) {
        CommitRowChips(
            commitSha: "abc1234",
            refs: GitRef.previewSamples,
            currentBranch: "main",
            onBranchDrop: nil
        )
    }
    .padding()
    .frame(width: 320)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
