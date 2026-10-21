import Foundation

nonisolated enum ThreadActionResult: Equatable, Sendable {
    case done
    /// The thread or the PR moved on the host (resolved, deleted, new
    /// commits): what's shown was reloaded, and the draft stays.
    case changedOnHost(String)
    case failed(String)
    /// Nothing to send (no PR, a blank draft, another send going).
    case ignored
}

extension PullRequestStore {
    /// Reads the selected PR's threads. A failure only sets `threadsError`:
    /// the detail and the diff stay as they are, and so do the threads,
    /// unless they were read against another diff (their lines may be other
    /// code now).
    func loadThreads() async {
        guard let pull = selected, let host else { return }
        threadsGen &+= 1
        let gen = threadsGen
        let detailGen = detailGen
        // Outdated is judged against the diff on screen.
        let shown = [filesDetail, detail].compactMap { $0 }.first { $0.pull.id == pull.id }
        let provider = makeReviewProvider(host)
        isLoadingThreads = true
        defer { if gen == threadsGen { isLoadingThreads = false } }
        do {
            let read = try await withToken(host) { token in
                try await provider.fetchThreads(host: host, pull: shown?.pull ?? pull, detail: shown, token: token)
            }
            guard gen == threadsGen, detailGen == self.detailGen, let read else { return }
            threads = read
            threadsHead = shown?.pull.headSha
            threadsError = nil
        } catch {
            guard gen == threadsGen, detailGen == self.detailGen else { return }
            if threadsHead != shown?.pull.headSha { threads = [] }
            threadsError = Self.message(for: error)
        }
    }

    /// Posts the draft on `target`'s line, pinned to the diff on screen,
    /// then closes the box and reloads the threads.
    func addComment(at target: CommentTarget) async -> ThreadActionResult {
        guard let pull = selected, let host else { return .ignored }
        let shown = filesDetail?.pull.id == pull.id ? filesDetail : nil
        return await send(.comment(pullId: pull.id, target: target), pull: pull, host: host) { provider, body, token in
            try await provider.addComment(host: host, pull: shown?.pull ?? pull, detail: shown, target: target,
                                          body: body, token: token)
        } onSent: { store in
            if store.composerTarget == target { store.composerTarget = nil }
        }
    }

    /// Posts the draft as an answer to `thread`, then closes its box and
    /// reloads the threads.
    func reply(to thread: ReviewThread) async -> ThreadActionResult {
        guard let pull = selected, let host else { return .ignored }
        return await send(.reply(pullId: pull.id, threadId: thread.id), pull: pull, host: host) { provider, body, token in
            try await provider.reply(host: host, pull: pull, thread: thread, body: body, token: token)
        } onSent: { store in
            if store.replyingThreadId == thread.id { store.replyingThreadId = nil }
        }
    }

    /// Resolves or reopens `thread`, then updates it in place: the host
    /// doesn't need asking again. Other threads can be resolved meanwhile.
    func setResolved(_ resolved: Bool, thread: ReviewThread) async -> ThreadActionResult {
        guard let pull = selected, let host, !resolvingThreadIds.contains(thread.id) else { return .ignored }
        resolvingThreadIds.insert(thread.id)
        defer { resolvingThreadIds.remove(thread.id) }
        let provider = makeReviewProvider(host)
        let outcome = await perform(.resolve, pull: pull, host: host) { token in
            try await provider.setResolved(resolved, host: host, pull: pull, thread: thread, token: token)
        }
        if outcome == .done, selected?.id == pull.id, let index = threads.firstIndex(where: { $0.id == thread.id }) {
            var updated = threads[index]
            let allowed = updated.canResolve || updated.canUnresolve
            updated.isResolved = resolved
            updated.resolvedBy = resolved ? currentUser : nil
            updated.canResolve = allowed && !resolved
            updated.canUnresolve = allowed && resolved
            threads[index] = updated
        }
        return outcome
    }

    // MARK: Focus

    /// Whether the box for `key` takes the focus as it comes on screen: once
    /// when it opens, and again only if it went off screen with it (scrolled
    /// away mid-sentence). Otherwise scrolling it back would take the focus
    /// from wherever the user is now.
    func claimFocus(_ key: ReviewDraftKey) -> Bool {
        guard focusRequest == key else { return false }
        focusRequest = nil
        return true
    }

    /// The box for `key` went off screen, with or without the focus. A box
    /// that closed has nothing to come back to.
    func composerLeft(_ key: ReviewDraftKey, hadFocus: Bool) {
        guard hadFocus, isOpen(key) else { return }
        focusRequest = key
    }

    private func isOpen(_ key: ReviewDraftKey) -> Bool {
        switch key {
        case .comment(let pullId, let target): selected?.id == pullId && composerTarget == target
        case .reply(let pullId, let threadId): selected?.id == pullId && replyingThreadId == threadId
        case .review(let pullId, let verdict): selected?.id == pullId && reviewPanel == verdict
        }
    }

    // MARK: Sending

    /// Sends the trimmed draft under `key`, once at a time per draft. The
    /// draft goes once it's posted, whichever PR is on screen by then; the
    /// box closes and the threads reload only if its PR still is, and the
    /// next send doesn't wait for that reload.
    private func send(_ key: ReviewDraftKey, pull: PullRequest, host: RemoteHost,
                      _ call: (PullRequestReviewProvider, _ body: String, _ token: String) async throws -> Void,
                      onSent: (PullRequestStore) -> Void) async -> ThreadActionResult {
        guard !sendingDrafts.contains(key) else { return .ignored }
        let body = (drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .ignored }
        sendingDrafts.insert(key)
        let provider = makeReviewProvider(host)
        let outcome = await perform(.comment, pull: pull, host: host) { token in try await call(provider, body, token) }
        sendingDrafts.remove(key)
        guard outcome == .done else { return outcome }
        drafts[key] = nil
        if selected?.id == pull.id {
            onSent(self)
            await loadThreads()
        }
        return outcome
    }

    /// Runs a write with the list's token. A thread that's gone reloads the
    /// threads; new commits reload the whole detail (threads with it).
    private func perform(_ action: PullRequestAction, pull: PullRequest, host: RemoteHost,
                         _ call: (String) async throws -> Void) async -> ThreadActionResult {
        do {
            guard try await withToken(host, call) != nil else {
                return .failed(Self.naming(pull, on: host, String(localized: "The account's token isn't available. Refresh the list.")))
            }
            return .done
        } catch {
            let failure = PullRequestActionError.from(error)
            let message = Self.naming(pull, on: host, failure.message(for: action, account: currentUser, host: host.host,
                                                                      isMergeRequest: host.provider == .gitlab))
            switch failure {
            case .changedOnHost:
                if selected?.id == pull.id { await loadThreads() }
                return .changedOnHost(message)
            case .headChanged:
                if selected?.id == pull.id { await loadDetail() }
                return .changedOnHost(message)
            case .forbidden, .pendingReview, .rejected, .other:
                return .failed(message)
            }
        }
    }
}
