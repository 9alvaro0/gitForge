import Foundation

/// The OAuth apps gitForge ships for github.com and gitlab.com (spec §5.1),
/// read from Info.plist (`GFGitHubOAuthClientID`, `GFGitLabOAuthClientID`).
/// Empty means not registered yet: that instance offers only tokens. Client
/// ids of public (device-flow) apps aren't secrets.
nonisolated struct OAuthClientIDs: Equatable, Sendable {
    var gitHub: String?
    var gitLab: String?

    static let none = OAuthClientIDs(gitHub: nil, gitLab: nil)

    static var bundled: OAuthClientIDs { from(Bundle.main.infoDictionary) }

    static func from(_ info: [String: Any]?) -> OAuthClientIDs {
        func value(_ key: String) -> String? {
            guard let raw = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
            return raw
        }
        return OAuthClientIDs(gitHub: value("GFGitHubOAuthClientID"), gitLab: value("GFGitLabOAuthClientID"))
    }
}

extension HostingInstance {
    /// github.com and gitlab.com with this build's client ids.
    nonisolated static func builtIns(clientIds: OAuthClientIDs) -> [HostingInstance] {
        var github = gitHubDotCom
        github.oauthClientId = clientIds.gitHub
        var gitlab = gitLabDotCom
        gitlab.oauthClientId = clientIds.gitLab
        return [github, gitlab]
    }
}
