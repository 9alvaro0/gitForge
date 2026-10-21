import Foundation

/// A write the user can do on a PR/MR, for error copy.
nonisolated enum PullRequestActionError: Error, Equatable, Sendable {
    /// The account isn't allowed (a fine-grained token without write, no
    /// merge rights…).
    case forbidden
    /// The head moved since the PR loaded (a pinned `sha` was refused).
    case headChanged
    /// GitHub: the user has a review pending, started on the web.
    case pendingReview
    /// What the action targets is gone or changed (thread resolved or deleted).
    case changedOnHost
    /// The host refused the action and said why.
    case rejected(String)
    case other(String)

    /// Maps a failed request. 401s never get here: `withToken` retries them.
    static func from(_ error: Error) -> PullRequestActionError {
        if let action = error as? PullRequestActionError { return action }
        guard let fetch = error as? PullRequestFetchError else { return .other(error.localizedDescription) }
        switch fetch {
        case .forbidden:
            return .forbidden
        case .notFound:
            return .changedOnHost
        case .server(409, _):
            return .headChanged
        case .server(422, let body) where body.range(of: "pending review", options: .caseInsensitive) != nil:
            return .pendingReview
        case .server(let status, let body) where [405, 406, 422].contains(status):
            return .rejected(hostMessage(fromBody: body))
        default:
            return .other(fetch.localizedDescription)
        }
    }

    /// What the host said: GitHub's `errors` (its `message` is a generic
    /// "Unprocessable Entity"), then `message` (a string, or GitLab's
    /// field → [reasons]), then `error`, then the body itself, cut short.
    static func hostMessage(fromBody body: String) -> String {
        if let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] {
            let reasons = (object["errors"] as? [Any] ?? []).compactMap { item in
                item as? String ?? (item as? [String: Any])?["message"] as? String
            }
            if !reasons.isEmpty { return reasons.joined(separator: "; ") }
            if let message = object["message"] as? String { return message }
            if let fields = object["message"] as? [String: [String]] {
                let reasons = fields.keys.sorted().flatMap { fields[$0] ?? [] }
                if !reasons.isEmpty { return reasons.joined(separator: "; ") }
            }
            if let error = object["error"] as? String { return error }
        }
        return String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    /// Whole sentences per action and noun, so translations can reorder them.
    func message(for action: PullRequestAction, account: String?, host: String, isMergeRequest: Bool) -> String {
        switch self {
        case .forbidden:
            return Self.forbidden(action, account: account ?? "?", host: host, isMergeRequest: isMergeRequest)
        case .headChanged:
            return action == .merge
                ? String(localized: "New commits were pushed — review them before merging.")
                : String(localized: "New commits were pushed — review them and try again.")
        case .pendingReview:
            return String(localized: "You have a pending review started on GitHub. Submit or discard it there first.")
        case .changedOnHost:
            return String(localized: "It changed on the host since it loaded. Reloaded.")
        case .rejected(let reason):
            return String(localized: "The host refused: \(reason)")
        case .other(let message):
            return message
        }
    }

    private static func forbidden(_ action: PullRequestAction, account: String, host: String, isMergeRequest: Bool) -> String {
        switch (action, isMergeRequest) {
        case (.comment, false): String(localized: "Your account (\(account) on \(host)) can't comment on this pull request.")
        case (.comment, true): String(localized: "Your account (\(account) on \(host)) can't comment on this merge request.")
        case (.resolve, false): String(localized: "Your account (\(account) on \(host)) can't resolve threads on this pull request.")
        case (.resolve, true): String(localized: "Your account (\(account) on \(host)) can't resolve threads on this merge request.")
        case (.approve, false): String(localized: "Your account (\(account) on \(host)) can't approve this pull request.")
        case (.approve, true): String(localized: "Your account (\(account) on \(host)) can't approve this merge request.")
        case (.requestChanges, false): String(localized: "Your account (\(account) on \(host)) can't request changes on this pull request.")
        case (.requestChanges, true): String(localized: "Your account (\(account) on \(host)) can't request changes on this merge request.")
        case (.merge, false): String(localized: "Your account (\(account) on \(host)) can't merge this pull request.")
        case (.merge, true): String(localized: "Your account (\(account) on \(host)) can't merge this merge request.")
        }
    }
}

/// Which write failed, for `PullRequestActionError.message`.
nonisolated enum PullRequestAction: Sendable {
    case comment, resolve, approve, requestChanges, merge
}
