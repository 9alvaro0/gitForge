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

    @Environment(\.appTheme) private var theme
    @State private var showHiddenRefs = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
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
            hasRemoteCounterpart: hasRemoteCounterpart(for: ref)
        )
        if ref.isLocalBranch, let onBranchDrop {
            chip
                .draggable(DraggedBranch(
                    name: ref.name,
                    isCurrent: isCurrent,
                    isLocal: true,
                    sourceSha: commitSha
                ))
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
        sortedRefs.count <= 2 ? sortedRefs : Array(sortedRefs.prefix(1))
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
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                        .fill(showHiddenRefs ? theme.palette.bg4 : theme.palette.bg3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                        .stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
                )
                .contentShape(.rect(cornerRadius: DesignTokens.Radius.chip))
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("\(hiddenRefs.count) more")
                .font(AppFont.sans(11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.palette.fg3)
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
        .padding(DesignTokens.Spacing.xl)
        .background(theme.palette.bg2)
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
    .background(theme.palette.bg1)
    .appTheme(theme)
}
