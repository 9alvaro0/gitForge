import Foundation

extension RemoteHost {
    static let previewGitHub = RemoteHost(
        provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge"
    )

    static let previewGitLab = RemoteHost(
        provider: .gitlab, host: "gitlab.com", owner: "group", repo: "project"
    )
}
