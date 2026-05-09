import SwiftUI

extension HistoryView {
    func resolveDrop(_ dropped: DraggedBranch, context: BranchDropContext) {
        guard let source = viewModel.refs.first(where: { $0.isLocalBranch && $0.name == dropped.name })
        else { return }

        switch context {
        case .onCommit(let targetSha):
            guard targetSha != dropped.sourceSha else { return }
            let shortSha = String(targetSha.prefix(7))
            if dropped.isCurrent {
                resetHeadRequest = ResetHeadRequest(
                    branchName: dropped.name,
                    targetSha: targetSha,
                    targetShortSha: shortSha
                )
            } else {
                moveBranchRequest = MoveBranchRequest(
                    branch: source,
                    targetSha: targetSha,
                    targetShortSha: shortSha
                )
            }
        case .onBranch(let targetBranchName, _):
            guard targetBranchName != dropped.name else { return }
            guard let target = viewModel.refs.first(where: {
                $0.isLocalBranch && $0.name == targetBranchName
            }) else { return }
            mergeRebaseRequest = MergeRebaseRequest(source: source, target: target)
        }
    }

    /// If a local branch points at the commit (and it's not already current),
    /// check that branch out — safer than a detached HEAD on the same SHA.
    /// Otherwise prompt before detaching.
    func handleDoubleClick(_ sha: String) {
        guard let commit = viewModel.commits.first(where: { $0.sha == sha }) else { return }
        let candidates = (viewModel.refsBySha[sha] ?? []).filter { ref in
            ref.isLocalBranch && ref.name != viewModel.currentBranchName
        }
        if let local = candidates.first {
            Task { await runCheckoutBranch(local) }
            return
        }
        if (viewModel.refsBySha[sha] ?? []).contains(where: {
            $0.isLocalBranch && $0.name == viewModel.currentBranchName
        }) {
            appState.ui.activeToast = ToastMessage(
                message: "Already on \(viewModel.currentBranchName ?? commit.shortSha)",
                kind: .ok
            )
            return
        }
        detachedCheckoutTarget = commit
    }

    func runCheckoutBranch(_ ref: GitRef) async {
        switch await viewModel.checkoutBranch(ref) {
        case .success:
            appState.ui.activeToast = ToastMessage(message: "Checked out \(ref.displayName)", kind: .ok)
        case .failure(let err):
            appState.ui.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    func runCheckoutCommit(_ commit: Commit) async {
        switch await viewModel.checkoutCommit(commit.sha) {
        case .success:
            appState.ui.activeToast = ToastMessage(message: "Detached HEAD at \(commit.shortSha)", kind: .ok)
        case .failure(let err):
            appState.ui.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    func runMove(_ request: MoveBranchRequest) {
        Task {
            switch await viewModel.moveBranch(request.branch, to: request.targetSha) {
            case .success:
                appState.ui.activeToast = ToastMessage(
                    message: "Moved \(request.branch.displayName) to \(request.targetShortSha)",
                    kind: .ok)
            case .failure(let err):
                appState.ui.activeToast = ToastMessage(
                    message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                    kind: .error)
            }
        }
    }

    func runReset(_ request: ResetHeadRequest, mode: GitCLI.ResetMode) {
        Task {
            let outcome = await viewModel.reset(to: request.targetSha, mode: mode)
            appState.ui.emitToast(
                for: outcome,
                success: "Reset \(request.branchName) to \(request.targetShortSha) (\(mode.rawValue))",
                conflicts: "Reset paused on conflicts — resolve to continue"
            )
        }
    }

    func runMerge(_ request: MergeRebaseRequest) {
        Task {
            let outcome = await viewModel.mergeBranch(source: request.source, into: request.target)
            appState.ui.emitToast(
                for: outcome,
                success: "Merged \(request.source.displayName) into \(request.target.displayName)",
                conflicts: "Merge has conflicts — resolve to continue"
            )
        }
    }

    func runRebase(_ request: MergeRebaseRequest) {
        Task {
            // Drop semantics: dragging X onto Y rebases X onto Y (X gets
            // replayed on top of Y). `rebaseOnto` rebases the CURRENT branch,
            // so we have to be on `source` first.
            if request.source.name != viewModel.currentBranchName {
                if case .failure(let err) = await viewModel.checkoutBranch(request.source) {
                    appState.ui.activeToast = ToastMessage(
                        message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                        kind: .error)
                    return
                }
            }
            let outcome = await viewModel.rebaseOnto(request.target)
            appState.ui.emitToast(
                for: outcome,
                success: "Rebased \(request.source.displayName) onto \(request.target.displayName)",
                conflicts: "Rebase has conflicts — resolve to continue"
            )
        }
    }
}
