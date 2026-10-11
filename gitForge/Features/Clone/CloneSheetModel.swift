import Foundation
import Observation

/// State of the "Clone a repository" sheet (artboard `Welcome`): the URL and
/// its reachability, the destination, the profile and, for a repo picked in
/// My repos, the account it was listed with.
@MainActor
@Observable
final class CloneSheetModel {
    enum ProbeState: Equatable {
        case idle
        case checking
        case done(RemoteProbeResult)
    }

    var url = "" {
        didSet { urlDidChange() }
    }
    var destination = "" {
        didSet { if destination != lastAutoDestination { destinationEdited = true } }
    }
    var branch = ""
    /// `nil`: keep the global identity.
    var profileId: UUID? {
        didSet { if profileId != suggestedProfileId { profileEdited = true } }
    }
    private(set) var probe: ProbeState = .idle

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let parentDirectory: String
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let runProbe: @Sendable (String) async -> RemoteProbeResult
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var lastAutoDestination = ""
    @ObservationIgnored private var destinationEdited = false
    @ObservationIgnored private var profileEdited = false
    @ObservationIgnored private var browsedURL: String?
    @ObservationIgnored private var browsedAccountId: UUID?

    /// - Parameters:
    ///   - parentDirectory: where the destination is proposed (the last
    ///     clone's parent).
    ///   - probe: checks a URL; the app passes `RemoteProbe.run` with its
    ///     credentials.
    init(store: AccountStore, parentDirectory: String, debounce: Duration = .milliseconds(600),
         probe: @escaping @Sendable (String) async -> RemoteProbeResult) {
        self.store = store
        self.parentDirectory = parentDirectory
        self.debounce = debounce
        self.runProbe = probe
    }

    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Checks the URL once typing pauses. A newer call (or URL) wins: the
    /// older one neither probes nor writes.
    func urlChanged() async {
        generation &+= 1
        let gen = generation
        let target = trimmedURL
        guard !target.isEmpty else {
            probe = .idle
            return
        }
        try? await Task.sleep(for: debounce)
        guard gen == generation, !Task.isCancelled else { return }
        probe = .checking
        let result = await runProbe(target)
        guard gen == generation, !Task.isCancelled else { return }
        probe = .done(result)
    }

    /// Fills the form from a "My repos" row: HTTPS, signed by `accountId`.
    func pick(_ repo: RemoteRepoSummary, accountId: UUID) {
        browsedURL = repo.httpsURL
        browsedAccountId = accountId
        url = repo.httpsURL
    }

    /// The account to pin for the clone: the listing account while the URL
    /// is still the picked one.
    var accountIdForClone: UUID? {
        trimmedURL == browsedURL ? browsedAccountId : nil
    }

    /// "GitHub · owner/repo · via login" for a URL on a declared instance.
    var remoteSummary: String? {
        guard let host = RemoteHost.parse(trimmedURL, instances: store.instances) else { return nil }
        return "\(host.provider.label) · \(host.slug) · \(signedBy(host))"
    }

    /// The profile linked to the account that will sign the clone.
    var suggestedProfileId: UUID? {
        signingAccount?.linkedProfileId
    }

    var canClone: Bool {
        guard !trimmedURL.isEmpty else { return false }
        let path = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        return !FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: Private

    private var isHTTPS: Bool { trimmedURL.lowercased().hasPrefix("https://") }

    private var signingAccount: HostingAccount? {
        if let id = accountIdForClone { return store.accounts.first { $0.id == id } }
        guard isHTTPS, let host = RemoteHost.parse(trimmedURL, instances: store.instances) else { return nil }
        let resolution = AccountResolver.resolve(remoteHost: host.host, remoteOwner: host.owner, repoPath: "",
                                                 remoteName: "origin", activeProfileId: nil,
                                                 instances: store.instances,
                                                 accounts: store.accounts.filter(AccountGitCredentials.signs),
                                                 assignments: [:])
        if case .account(let account) = resolution { return account }
        return nil
    }

    private func signedBy(_ host: RemoteHost) -> String {
        guard isHTTPS else { return "SSH" }
        if let login = signingAccount?.login { return "via \(login)" }
        return "system credentials"
    }

    private func urlDidChange() {
        if !destinationEdited, let leaf = Self.repoName(from: trimmedURL) {
            let proposed = "\(parentDirectory)/\(leaf)"
            lastAutoDestination = proposed
            destination = proposed
        }
        if !profileEdited { profileId = suggestedProfileId }
    }

    /// The last path segment without `.git`.
    static func repoName(from url: String) -> String? {
        guard let last = url.split(whereSeparator: { $0 == "/" || $0 == ":" }).last else { return nil }
        var name = String(last)
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name.isEmpty ? nil : name
    }
}
